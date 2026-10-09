# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ChoiceLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        partition_selector: DecisionContexts::PartitionSelector.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @partition_selector = partition_selector
        @canonical_json = canonical_json
      end

      def call(choice_id:, accepted_choice:)
        events = @event_store.read(
          @stream_factory.agent_choice(choice_id),
          EventQueries::AGENT_CHOICE_FOR_IMPACT
        )
        payloads = events.map { load(_1) }
        validate_history!(choice_id, accepted_choice, events, payloads)

        ChoiceSnapshotV1.new(
          choice_id:,
          recorded: payloads.fetch(0),
          recorded_event: reference(events.fetch(0)),
          accepted: payloads.fetch(1),
          accepted_event: reference(events.fetch(1)),
          invalidation: payloads.fetch(2, nil),
          invalidation_event: events[2] && reference(events.fetch(2))
        )
      end

      private

      def validate_history!(choice_id, expected_accepted, events, payloads)
        valid_pair = payloads.first(2).map(&:class) ==
          [ Events::AgentChoiceRecordedV2, Events::AgentChoiceAcceptedV2 ]
        valid_invalidation = payloads.length == 2 ||
          payloads.last.is_a?(Events::AgentChoiceInvalidatedByDecisionV2)
        unless payloads.length.between?(2, 3) && valid_pair && valid_invalidation
          invalid!("choice_lifecycle_invalid", choice_id:, event_types: events.map(&:type))
        end

        recorded = payloads.fetch(0)
        accepted = payloads.fetch(1)
        recorded_reference = reference(events.fetch(0))
        accepted_reference = reference(events.fetch(1))
        context_digest = events.fetch(1).metadata["context_digest"]
        valid_identity = recorded.choice_id == choice_id &&
                         accepted.choice_id == choice_id &&
                         recorded_reference.stream_revision == 0 &&
                         accepted_reference.stream_revision == 1 &&
                         accepted_reference == expected_accepted
        unless valid_identity
          invalid!(
            "choice_identity_invalid",
            choice_id:,
            expected_accepted: expected_accepted.to_h,
            persisted_accepted: accepted_reference.to_h
          )
        end

        validate_context!(recorded, context_digest:)
        invalidation = payloads.fetch(2, nil)
        validate_current_invalidation!(choice_id, accepted_reference, events.fetch(2), invalidation) if invalidation
      end

      def validate_context!(recorded, context_digest:)
        context = recorded.decision_context
        document = context.document
        expected_partitions = @partition_selector.call(recorded.context)
        canonical_digest = @canonical_json.sha256(document.to_h)
        observations_valid = document.partitions.map(&:partition) == expected_partitions &&
                             document.partitions.all? { valid_observation?(_1) }
        unless document.query_context == recorded.context &&
               context_digest == canonical_digest &&
               observations_valid
          invalid!(
            "recorded_context_invalid",
            choice_id: recorded.choice_id,
            context_digest:
          )
        end
      end

      def valid_observation?(observation)
        if observation.partition_revision.nil?
          return observation.event.nil? && observation.active_decisions.empty?
        end

        event = observation.event
        heads = observation.active_decisions
        event &&
          %w[DecisionAddedToPartition DecisionRemovedFromPartition].include?(event.type) &&
          event.stream_context == "HumanGuidance" &&
          event.stream_name == "DecisionPartition" &&
          event.stream_id == observation.partition.partition_id &&
          event.stream_revision == observation.partition_revision &&
          heads.map(&:decision_id).uniq.length == heads.length &&
          heads == heads.sort_by { _1.decision_id.b } &&
          heads.all? { exact_decision_head?(_1) }
      end

      def exact_decision_head?(head)
        head.decision_revision == head.event.stream_revision &&
          head.event.stream_context == "HumanGuidance" &&
          head.event.stream_name == "Decision" &&
          head.event.stream_id == head.decision_id
      end

      def validate_current_invalidation!(choice_id, accepted_reference, event, invalidation)
        assessment_id = assessment_id_from(event)
        assessment_events = assessment_id && @event_store.read(
          @stream_factory.agent_choice_impact(assessment_id),
          EventReadCriteria.new(
            event_types: %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked],
            maximum_count: 3,
            direction: :asc
          )
        )
        assessment_payloads = assessment_events&.map { load(_1) }
        assessment_event = assessment_events&.first
        assessment = assessment_payloads&.fetch(0, nil)
        links = assessment_payloads&.drop(1) || []
        accepted_link = links.find { _1.is_a?(Events::AgentChoiceImpactSourceLinkedV1) && _1.role == "accepted_choice" }
        decision_link = links.find { _1.is_a?(Events::AgentChoiceImpactSourceLinkedV1) && _1.role == "decision_change" }
        before_digest = assessment_event&.metadata&.fetch("before_context_digest", nil)
        after_digest = assessment_event&.metadata&.fetch("after_context_digest", nil)
        valid = reference(event).stream_revision == 2 &&
                invalidation.choice_id == choice_id &&
                assessment_events&.map(&:stream_revision) == [ 0, 1, 2 ] &&
                assessment.is_a?(Events::AgentChoiceImpactAssessmentRecordedV1) &&
                assessment.assessment_id == assessment_id &&
                assessment.choice_id == choice_id &&
                links.all? { _1.assessment_id == assessment_id } &&
                assessment.assessment.outcome == "invalidated" &&
                assessment.assessment.reason == invalidation.reason &&
                accepted_link&.source == accepted_reference &&
                decision_link && valid_decision_change_reference?(decision_link.source) &&
                event.markers.include?("decision:#{decision_link.source.stream_id}") &&
                event.markers.include?("decision-change:#{decision_link.source.event_id}") &&
                Types::SHA256_DIGEST_PATTERN.match?(before_digest.to_s) &&
                Types::SHA256_DIGEST_PATTERN.match?(after_digest.to_s) &&
                before_digest != after_digest &&
                event.metadata["policy_version"] == assessment_event.metadata["policy_version"] &&
                event.metadata["previous_context_digest"] == before_digest &&
                event.metadata["resulting_context_digest"] == after_digest
        invalid!("choice_invalidation_invalid", choice_id:) unless valid
      end

      def assessment_id_from(event)
        markers = event.markers.grep(/\Aimpact-assessment:/)
        return unless markers.length == 1

        markers.sole.delete_prefix("impact-assessment:")
      end

      def valid_decision_change_reference?(source)
        %w[DecisionActivated DecisionDefinitionCorrected].include?(source.type) &&
          source.stream_context == "HumanGuidance" &&
          source.stream_name == "Decision"
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
