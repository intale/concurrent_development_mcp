# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class ReleaseSets
      include EventTimestamped

      def fetch(release_set_id)
        record = Coordinator::Read::ReleaseSet.find_by(release_set_id:)
        record && build_view(record)
      end

      def store(event:, preparation:)
        create_from_event(Coordinator::Read::ReleaseSet, event:, attributes: {
          release_set_id: preparation.release_set_id,
          change_set_id: preparation.change_set_id,
          ordered_members: preparation.ordered_members.map(&:to_h),
          release_digest: preparation.release_digest,
          status: "prepared",
          verification_status: "unverified",
          integrations: [],
          verifications: [],
          activation: nil,
          compensation_request: nil,
          completion: nil,
          preparation_policy_version: preparation.policy_version,
          prepared_at_domain: event.created_at,
          prepared_event: event_reference(event).to_h,
          prepared_actor: actor(event).to_h,
          prepared_markers: event.markers,
          prepared_metadata: event.metadata,
          prepared_causation_id: event.causation_id,
          prepared_correlation_id: event.correlation_id,
          prepared_global_position: event.global_position,
          prepared_at_store: event.created_at
        })
      end

      def record_integration(event:, integration:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: integration.release_set_id)
        integrations = record.integrations + [ integration_view(event:, integration:).to_h ]
        save_from_event(record, event:, attributes: {
          integrations:,
          status: every_member_integrated?(record.ordered_members, integrations) ? "verifying" : "integrating"
        })
      end

      def link_integration(event:, link:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: link.release_set_id)
        integrations = record.integrations.dup
        index = integrations.rindex do |entry|
          values = symbolize(entry)
          values.fetch(:repository_id) == link.repository_id &&
            values.fetch(:outcome) == "integrated" && values[:merge_observation_event].nil?
        end
        raise InvalidProjectionSource, "Repository integration merge link is orphaned" unless index

        integrations[index] = integrations.fetch(index).merge(
          "merge_observation_event" => link.merge_observation.to_h,
          "observation_digest" => observation_digest(record, index)
        )
        save_from_event(record, event:, attributes: {
          integrations:,
          status: every_member_integrated?(record.ordered_members, integrations) ? "verifying" : "integrating"
        })
      end

      def record_verification(event:, verification:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: verification.release_set_id)
        save_from_event(record, event:, attributes: {
          verifications: record.verifications + [ verification_view(event:, verification:).to_h ],
          verification_status: verification.evidence.outcome,
          status: verification.evidence.outcome == "passed" ? "verified" : "verifying"
        })
      end

      def link_verification_integration(event:, link:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: link.release_set_id)
        verifications = record.verifications.dup
        raise InvalidProjectionSource, "ReleaseSet verification integration link is orphaned" if verifications.empty?

        latest = verifications.last
        latest["integration_events"] = [ *latest.fetch("integration_events"), link.integration_event.to_h ]
        latest["integration_link_events"] = [ *latest.fetch("integration_link_events", []), event_reference(event).to_h ]
        verifications[-1] = latest
        save_from_event(record, event:, attributes: { verifications: })
      end

      def record_activation(event:, activation:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: activation.release_set_id)
        save_from_event(
          record,
          event:,
          attributes: { activation: activation_view(record, event:, activation:).to_h, status: "activated" }
        )
      end

      def record_compensation_request(event:, request:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: request.release_set_id)
        save_from_event(record, event:, attributes: {
          compensation_request: compensation_request_view(event:, request:).to_h,
          status: "compensation_requested"
        })
      end

      def link_compensation_integration(event:, link:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: link.release_set_id)
        request = record.compensation_request&.dup
        raise InvalidProjectionSource, "Compensation integration link is orphaned" unless request

        request["successful_integrations"] = [ *request.fetch("successful_integrations"), link.integration_event.to_h ]
        request["integration_link_events"] = [ *request.fetch("integration_link_events", []), event_reference(event).to_h ]
        save_from_event(record, event:, attributes: { compensation_request: request })
      end

      def record_repository_compensation(event:, compensation:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: compensation.release_set_id)
        values = record.completion&.dup || { "compensation_evidence" => [] }
        evidence = Coordinator::Write::ReleaseSets::CompensationEvidenceV2.new(
          repository_id: compensation.repository_id,
          integration_event: compensation.integration_event,
          action: compensation.action,
          external_reference: compensation.external_reference,
          result_digest: event.metadata.fetch("result_digest"),
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(
            symbolize(event.metadata.fetch("producer"))
          ),
          run_id: event.metadata.fetch("run_id")
        )
        values["compensation_evidence"] = [ *values.fetch("compensation_evidence", []), evidence.to_h ]
        save_from_event(record, event:, attributes: { completion: values })
      end

      def record_outcome(event:, outcome:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: outcome.release_set_id)
        evidence = record.completion&.fetch("compensation_evidence", []) || []
        save_from_event(
          record,
          event:,
          attributes: { completion: completion_view(event:, outcome:, compensation_evidence: evidence).to_h }
        )
      end

      def record_completion(event:, completion:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: completion.release_set_id)
        values = record.completion&.dup
        raise InvalidProjectionSource, "ReleaseSet completion has no outcome" unless values

        values["completed_at"] = event.created_at.utc.iso8601(6)
        values["source"] = source_evidence_from_event(event).to_h
        save_from_event(record, event:, attributes: { completion: values, status: "completed" })
      end

      private

      def build_view(record)
        ReleaseSetViewV1.new(
          release_set_id: record.release_set_id,
          change_set_id: record.change_set_id,
          ordered_members: record.ordered_members.map { ReleaseSetMemberViewV1.new(symbolize(_1)) },
          release_digest: record.release_digest,
          status: record.status,
          verification_status: record.verification_status,
          integrations: record.integrations.map { build_integration(_1) },
          verifications: record.verifications.map { build_verification(_1) },
          activation: record.activation && build_activation(record.activation),
          compensation_request: record.compensation_request && build_compensation_request(record.compensation_request),
          completion: record.completion&.key?("outcome") && build_completion(record.completion),
          preparation_policy_version: record.preparation_policy_version,
          prepared_at: record.prepared_at_domain.utc.iso8601(6),
          prepared: source_evidence(record)
        )
      end

      def integration_view(event:, integration:)
        ReleaseSetIntegrationViewV1.new(
          repository_id: integration.repository_id,
          member_position: integration.member_position,
          attempt_id: integration.attempt_id,
          attempt_number: integration.attempt_number,
          outcome: integration.outcome,
          merge_observation_event: nil,
          observation_digest: event.metadata["observation_digest"],
          failure: integration.failure,
          integration_digest: event.metadata.fetch("integration_digest"),
          policy_version: event.metadata.fetch("policy_version"),
          evidence_status: "attributed_unverified",
          recorded_at: event.created_at.utc.iso8601(6),
          source: source_evidence_from_event(event)
        )
      end

      def verification_view(event:, verification:)
        ReleaseSetVerificationViewV1.new(
          attempt_number: verification.attempt_number,
          integration_events: [],
          evidence: verification.evidence,
          verification_digest: event.metadata.fetch("verification_digest"),
          policy_version: event.metadata.fetch("policy_version"),
          evidence_status: "attributed_unverified",
          recorded_at: event.created_at.utc.iso8601(6),
          source: source_evidence_from_event(event)
        )
      end

      def activation_view(record, event:, activation:)
        verification = record.verifications.last
        ReleaseSetActivationViewV1.new(
          verification_event: verification && event_reference_value(verification.dig("source", "event")),
          verification_digest: event.metadata.fetch("verification_digest"),
          activation_point: activation.activation_point,
          activation_digest: event.metadata.fetch("activation_digest"),
          policy_version: event.metadata.fetch("policy_version"),
          evidence_status: "attributed_unverified",
          recorded_at: event.created_at.utc.iso8601(6),
          source: source_evidence_from_event(event)
        )
      end

      def compensation_request_view(event:, request:)
        ReleaseSetCompensationRequestViewV1.new(
          trigger_event: nil,
          trigger_kind: request.trigger_kind,
          successful_integrations: [],
          reason: request.reason,
          rule_version: event.metadata.fetch("rule_version"),
          requested_at: event.created_at.utc.iso8601(6),
          source: source_evidence_from_event(event)
        )
      end

      def completion_view(event:, outcome:, compensation_evidence:)
        ReleaseSetCompletionViewV1.new(
          outcome: outcome.outcome,
          source_event: nil,
          compensation_evidence: compensation_evidence.map { compensation_evidence_value(symbolize(_1)) },
          completion_digest: event.metadata.fetch("completion_digest"),
          rule_version: event.metadata.fetch("rule_version"),
          completed_at: event.created_at.utc.iso8601(6),
          source: source_evidence_from_event(event)
        )
      end

      def build_integration(attributes)
        values = symbolize(attributes)
        ReleaseSetIntegrationViewV1.new(
          **values,
          merge_observation_event: event_reference_value(values[:merge_observation_event]),
          failure: integration_failure_value(values[:failure]),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_verification(attributes)
        values = symbolize(attributes)
        ReleaseSetVerificationViewV1.new(
          **values.except(:integration_link_events),
          integration_events: values.fetch(:integration_events).map { Coordinator::Write::EventReference.new(_1) },
          evidence: verification_evidence_value(values.fetch(:evidence)),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_activation(attributes)
        values = symbolize(attributes)
        point = values.fetch(:activation_point)
        ReleaseSetActivationViewV1.new(
          **values,
          verification_event: event_reference_value(values[:verification_event]),
          activation_point: Coordinator::Write::ReleaseSets::ActivationPointV2.new(
            **point,
            producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(point.fetch(:producer))
          ),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_compensation_request(attributes)
        values = symbolize(attributes)
        ReleaseSetCompensationRequestViewV1.new(
          **values.except(:integration_link_events),
          trigger_event: event_reference_value(values[:trigger_event]),
          successful_integrations: values.fetch(:successful_integrations).map do |reference|
            Coordinator::Write::EventReference.new(reference)
          end,
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def build_completion(attributes)
        values = symbolize(attributes)
        ReleaseSetCompletionViewV1.new(
          **values,
          source_event: event_reference_value(values[:source_event]),
          compensation_evidence: values.fetch(:compensation_evidence).map { compensation_evidence_value(_1) },
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def observation_digest(record, index)
        symbolize(record.integrations.fetch(index)).fetch(:observation_digest)
      end

      def event_reference_value(attributes)
        return unless attributes
        return attributes if attributes.is_a?(Coordinator::Write::EventReference)

        Coordinator::Write::EventReference.new(symbolize(attributes))
      end

      def integration_failure_value(attributes)
        return unless attributes

        Coordinator::Write::ReleaseSets::IntegrationFailureV2.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def verification_evidence_value(attributes)
        Coordinator::Write::ReleaseSets::VerificationEvidenceV2.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer)),
          findings: attributes.fetch(:findings).map { Coordinator::Write::ReleaseSets::VerificationFindingV1.new(_1) }
        )
      end

      def compensation_evidence_value(attributes)
        Coordinator::Write::ReleaseSets::CompensationEvidenceV2.new(
          **attributes,
          integration_event: Coordinator::Write::EventReference.new(attributes.fetch(:integration_event)),
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def every_member_integrated?(members, integrations)
        latest = integrations.each_with_object({}) do |integration, result|
          values = symbolize(integration)
          result[values.fetch(:repository_id)] = values.fetch(:outcome) if values[:merge_observation_event]
        end
        members.all? { latest[symbolize(_1).fetch(:repository_id)] == "integrated" }
      end

      def source_evidence(record)
        ReleaseSetSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.prepared_event)),
          actor: AttributedActorV1.new(symbolize(record.prepared_actor)),
          markers: record.prepared_markers,
          metadata: record.prepared_metadata,
          global_position: record.prepared_global_position,
          occurred_at: record.prepared_at_domain.utc.iso8601(6),
          persisted_at: record.prepared_at_store.utc.iso8601(6),
          causation_id: record.prepared_causation_id,
          correlation_id: record.prepared_correlation_id
        )
      end

      def source_evidence_from_event(event)
        ReleaseSetSourceEvidenceV1.new(
          event: event_reference(event),
          actor: actor(event),
          markers: event.markers,
          metadata: event.metadata,
          global_position: event.global_position,
          occurred_at: event.created_at.utc.iso8601(6),
          persisted_at: event.created_at.utc.iso8601(6),
          causation_id: event.causation_id,
          correlation_id: event.correlation_id
        )
      end

      def source_evidence_value(attributes)
        ReleaseSetSourceEvidenceV1.new(
          **attributes,
          event: Coordinator::Write::EventReference.new(attributes.fetch(:event)),
          actor: AttributedActorV1.new(attributes.fetch(:actor))
        )
      end

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: event.metadata.fetch("actor_authenticated", false)
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
