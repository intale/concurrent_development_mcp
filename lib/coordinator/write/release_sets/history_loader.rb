# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class HistoryLoader
      def initialize(
        event_store:,
        candidate_state_loader: Candidates::StateLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @candidate_state_loader = candidate_state_loader
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(release_set_id)
        facts = empty_facts
        @event_store.read(
          @stream_factory.release_set(release_set_id),
          EventQueries::RELEASE_SET_LIFECYCLE
        ).each do |event|
          payload = load_event(event)
          validate_identity!(payload, release_set_id:, event:)
          apply!(facts, payload:, event:)
        end
        validate_complete_history!(facts)
        Domain::ReleaseSets::LifecycleStateV2.new(
          preparation: facts[:preparation],
          integrations: facts[:integrations].freeze,
          verifications: facts[:verifications].freeze,
          activation: facts[:activation],
          compensation_request: facts[:compensation_request],
          compensation_evidence: facts[:compensation_evidence].freeze,
          completion: facts[:completion]
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidReleaseSetHistory, error.message
      end

      private

      def empty_facts
        {
          created: nil,
          members: [],
          preparation: nil,
          integrations: [],
          verifications: [],
          activation: nil,
          compensation_request: nil,
          compensation_evidence: [],
          pending_outcome: nil,
          completion: nil
        }
      end

      def apply!(facts, payload:, event:)
        case payload
        when Events::ReleaseSetCreatedV1 then apply_created!(facts, payload)
        when Events::ReleaseSetMemberAddedV1 then apply_member!(facts, payload)
        when Events::ReleaseSetPreparedV2 then apply_prepared!(facts, payload, event)
        when Events::RepositoryIntegrationRecordedV2 then apply_integration!(facts, payload, event)
        when Events::RepositoryIntegrationMergeLinkedV1 then apply_merge_link!(facts, payload, event)
        when Events::ReleaseSetVerificationRecordedV2 then apply_verification!(facts, payload, event)
        when Events::ReleaseSetIntegrationLinkedV1 then apply_integration_link!(facts, payload, event)
        when Events::ReleaseSetActivatedV2 then apply_activation!(facts, payload, event)
        when Events::ReleaseSetCompensationRequestedV2 then apply_compensation!(facts, payload, event)
        when Events::ReleaseSetSuccessfulIntegrationLinkedV1 then apply_success_link!(facts, payload, event)
        when Events::RepositoryCompensationRecordedV1 then apply_repository_compensation!(facts, payload, event)
        when Events::ReleaseSetOutcomeRecordedV1 then apply_outcome!(facts, payload, event)
        when Events::ReleaseSetCompletedV2 then apply_completion!(facts, event)
        end
      end

      def apply_created!(facts, payload)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate creation facts" if facts[:created]
        raise InvalidReleaseSetHistory, "ReleaseSet creation appeared after preparation" if facts[:preparation]

        facts[:created] = payload
      end

      def apply_member!(facts, payload)
        raise InvalidReleaseSetHistory, "ReleaseSet member appeared before creation" unless facts[:created]
        raise InvalidReleaseSetHistory, "ReleaseSet member appeared after preparation" if facts[:preparation]
        unless payload.member_position == facts[:members].length + 1
          raise InvalidReleaseSetHistory, "ReleaseSet member positions are not contiguous"
        end
        if facts[:members].any? { _1.repository_id == payload.repository_id }
          raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate repositories"
        end

        candidates = payload.ordered_candidate_ids.map do |candidate_id|
          candidate = @candidate_state_loader.call(candidate_id)
          unless candidate && candidate.repository_id == payload.repository_id
            raise InvalidReleaseSetHistory,
                  "ReleaseSet member Candidate is absent or belongs to another repository"
          end

          candidate
        end
        facts[:members] << MemberV2.new(
          position: payload.member_position,
          repository_id: payload.repository_id,
          merge_snapshot_id: payload.merge_snapshot_id,
          ordered_candidate_ids: payload.ordered_candidate_ids,
          authorization_event: payload.authorization_event,
          ordered_candidates: candidates.freeze
        )
      end

      def apply_prepared!(facts, payload, event)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate preparation facts" if facts[:preparation]
        created = facts[:created]
        raise InvalidReleaseSetHistory, "ReleaseSet preparation appeared before creation" unless created
        unless facts[:members].length.between?(Types::RELEASE_SET_MINIMUM_MEMBERS, Types::RELEASE_SET_MAXIMUM_MEMBERS)
          raise InvalidReleaseSetHistory, "ReleaseSet preparation has an invalid member count"
        end

        state = PreparedStateV2.new(
          release_set_id: payload.release_set_id,
          change_set_id: created.change_set_id,
          ordered_members: facts[:members].freeze,
          release_digest: event.metadata.fetch("release_digest"),
          policy_version: event.metadata.fetch("policy_version")
        )
        facts[:preparation] = PreparationFactV2.new(
          payload: state,
          event: event_reference(event),
          correlation_id: event.correlation_id
        )
      end

      def apply_integration!(facts, payload, event)
        require_preparation!(facts)
        facts[:integrations] << IntegrationFactV2.new(
          payload:,
          event: event_reference(event),
          merge_observation: nil,
          merge_link_event: nil,
          integration_digest: event.metadata.fetch("integration_digest"),
          observation_digest: event.metadata["observation_digest"],
          release_digest: event.metadata.fetch("release_digest"),
          policy_version: event.metadata.fetch("policy_version")
        )
      end

      def apply_merge_link!(facts, payload, event)
        integration = facts[:integrations].last
        unless integration && integration.payload.repository_id == payload.repository_id &&
               integration.payload.outcome == "integrated" && integration.merge_observation.nil?
          raise InvalidReleaseSetHistory, "Repository integration merge link is orphaned"
        end

        facts[:integrations][-1] = integration.new(
          merge_observation: payload.merge_observation,
          merge_link_event: event_reference(event)
        )
      end

      def apply_verification!(facts, payload, event)
        require_preparation!(facts)
        facts[:verifications] << VerificationFactV2.new(
          payload:,
          event: event_reference(event),
          integration_events: [],
          integration_link_events: [],
          release_digest: event.metadata.fetch("release_digest"),
          verification_digest: event.metadata.fetch("verification_digest"),
          policy_version: event.metadata.fetch("policy_version")
        )
      end

      def apply_integration_link!(facts, payload, event)
        verification = facts[:verifications].last
        raise InvalidReleaseSetHistory, "ReleaseSet verification integration link is orphaned" unless verification
        unless facts[:integrations].any? { _1.event == payload.integration_event }
          raise InvalidReleaseSetHistory, "ReleaseSet verification links unknown integration"
        end

        facts[:verifications][-1] = verification.new(
          integration_events: [ *verification.integration_events, payload.integration_event ].freeze,
          integration_link_events: [ *verification.integration_link_events, event_reference(event) ].freeze
        )
      end

      def apply_activation!(facts, payload, event)
        require_preparation!(facts)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate activation facts" if facts[:activation]

        facts[:activation] = ActivationFactV2.new(
          payload:,
          event: event_reference(event),
          activation_digest: event.metadata.fetch("activation_digest"),
          release_digest: event.metadata.fetch("release_digest"),
          verification_digest: event.metadata.fetch("verification_digest"),
          policy_version: event.metadata.fetch("policy_version")
        )
      end

      def apply_compensation!(facts, payload, event)
        require_preparation!(facts)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate compensation requests" if facts[:compensation_request]

        facts[:compensation_request] = CompensationRequestFactV2.new(
          payload:,
          event: event_reference(event),
          successful_integrations: [],
          integration_link_events: [],
          release_digest: event.metadata.fetch("release_digest"),
          rule_version: event.metadata.fetch("rule_version")
        )
      end

      def apply_success_link!(facts, payload, event)
        request = facts[:compensation_request]
        raise InvalidReleaseSetHistory, "Compensation integration link is orphaned" unless request
        unless facts[:integrations].any? { _1.event == payload.integration_event && _1.payload.outcome == "integrated" }
          raise InvalidReleaseSetHistory, "Compensation links unknown successful integration"
        end

        facts[:compensation_request] = request.new(
          successful_integrations: [ *request.successful_integrations, payload.integration_event ].freeze,
          integration_link_events: [ *request.integration_link_events, event_reference(event) ].freeze
        )
      end

      def apply_repository_compensation!(facts, payload, event)
        request = facts[:compensation_request]
        raise InvalidReleaseSetHistory, "Repository compensation appeared before its request" unless request
        raise InvalidReleaseSetHistory, "Repository compensation appeared after terminal outcome" if facts[:pending_outcome] || facts[:completion]
        unless request.successful_integrations.include?(payload.integration_event)
          raise InvalidReleaseSetHistory, "Repository compensation references an unrequested integration"
        end
        integration = facts[:integrations].find { _1.event == payload.integration_event }
        unless integration&.payload&.repository_id == payload.repository_id
          raise InvalidReleaseSetHistory, "Repository compensation identity does not match its integration"
        end
        if facts[:compensation_evidence].any? { _1.integration_event == payload.integration_event }
          raise InvalidReleaseSetHistory, "Repository compensation contains duplicate integration evidence"
        end

        facts[:compensation_evidence] << CompensationEvidenceV2.new(
          repository_id: payload.repository_id,
          integration_event: payload.integration_event,
          action: payload.action,
          external_reference: payload.external_reference,
          result_digest: event.metadata.fetch("result_digest"),
          producer: EvidenceProducerV1.new(event.metadata.fetch("producer").transform_keys(&:to_sym)),
          run_id: event.metadata.fetch("run_id")
        )
      end

      def apply_outcome!(facts, payload, event)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate terminal outcomes" if facts[:pending_outcome] || facts[:completion]
        validate_compensation_evidence!(facts, payload)
        facts[:pending_outcome] = [ payload, event ]
      end

      def apply_completion!(facts, event)
        raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate completion facts" if facts[:completion]
        outcome, outcome_event = facts[:pending_outcome]
        raise InvalidReleaseSetHistory, "ReleaseSet completion has no outcome" unless outcome

        facts[:completion] = CompletionFactV2.new(
          payload: outcome,
          outcome_event: event_reference(outcome_event),
          event: event_reference(event),
          compensation_evidence: facts[:compensation_evidence].freeze,
          completion_digest: outcome_event.metadata.fetch("completion_digest"),
          release_digest: outcome_event.metadata.fetch("release_digest"),
          rule_version: outcome_event.metadata.fetch("rule_version")
        )
        facts[:pending_outcome] = nil
      end

      def validate_complete_history!(facts)
        if facts[:integrations].any? { _1.payload.outcome == "integrated" && _1.merge_observation.nil? }
          raise InvalidReleaseSetHistory, "Successful repository integration has no merge link"
        end
        if facts[:pending_outcome]
          raise InvalidReleaseSetHistory, "ReleaseSet terminal outcome has no completion fact"
        end
      end

      def require_preparation!(facts)
        raise InvalidReleaseSetHistory, "ReleaseSet lifecycle fact appeared before preparation" unless facts[:preparation]
      end

      def validate_compensation_evidence!(facts, outcome)
        if outcome.outcome == "compensated"
          request = facts[:compensation_request]
          expected = request&.successful_integrations || []
          actual = facts[:compensation_evidence].map(&:integration_event)
          unless actual == expected
            raise InvalidReleaseSetHistory, "Compensated ReleaseSet is missing exact repository evidence"
          end
        elsif facts[:compensation_evidence].any?
          raise InvalidReleaseSetHistory, "Activated ReleaseSet cannot contain compensation evidence"
        end
      end

      def validate_identity!(payload, release_set_id:, event:)
        return if payload.release_set_id == release_set_id && event.stream.stream_id == release_set_id

        raise InvalidReleaseSetHistory, "ReleaseSet event identity does not match its stream"
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
