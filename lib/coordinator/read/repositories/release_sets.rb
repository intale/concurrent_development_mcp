# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class ReleaseSets
      def fetch(release_set_id)
        record = Coordinator::Read::ReleaseSet.find_by(release_set_id:)
        record && build_view(record)
      end

      def store(event:, release_set:)
        Coordinator::Read::ReleaseSet.create!(
          release_set_id: release_set.release_set_id,
          change_set_id: release_set.change_set_id,
          ordered_members: release_set.ordered_members.map(&:to_h),
          release_digest: release_set.release_digest,
          status: "prepared",
          verification_status: "unverified",
          integrations: [],
          verifications: [],
          preparation_policy_version: release_set.policy_version,
          prepared_at_domain: release_set.prepared_at,
          prepared_event: event_reference(event).to_h,
          prepared_actor: actor(event).to_h,
          prepared_markers: event.markers,
          prepared_metadata: event.metadata,
          prepared_causation_id: event.causation_id,
          prepared_correlation_id: event.correlation_id,
          prepared_global_position: event.global_position,
          prepared_at_store: event.created_at
        )
      end

      def record_integration(event:, integration:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: integration.release_set_id)
        integrations = record.integrations + [ integration_view(event:, integration:).to_h ]
        record.update!(
          integrations:,
          status: every_member_integrated?(record.ordered_members, integrations) ? "verifying" : "integrating"
        )
      end

      def record_verification(event:, verification:)
        record = Coordinator::Read::ReleaseSet.find_by!(release_set_id: verification.release_set_id)
        record.update!(
          verifications: record.verifications + [ verification_view(event:, verification:).to_h ],
          verification_status: verification.evidence.outcome,
          status: verification.evidence.outcome == "passed" ? "verified" : "verifying"
        )
      end

      private

      def build_view(record)
        ReleaseSetViewV1.new(
          release_set_id: record.release_set_id,
          change_set_id: record.change_set_id,
          ordered_members: record.ordered_members.map do |member|
            Coordinator::Write::ReleaseSets::MemberEvidenceV1.new(symbolize(member))
          end,
          release_digest: record.release_digest,
          status: record.status,
          verification_status: record.verification_status,
          integrations: record.integrations.map { build_integration(_1) },
          verifications: record.verifications.map { build_verification(_1) },
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
          merge_observation_event: integration.merge_observation_event,
          observation_digest: integration.observation_digest,
          failure: integration.failure,
          integration_digest: integration.integration_digest,
          policy_version: integration.policy_version,
          evidence_status: integration.evidence_status,
          recorded_at: integration.recorded_at,
          source: source_evidence_from_event(event, occurred_at: integration.recorded_at)
        )
      end

      def verification_view(event:, verification:)
        ReleaseSetVerificationViewV1.new(
          attempt_number: verification.attempt_number,
          integration_events: verification.integration_events,
          evidence: verification.evidence,
          verification_digest: verification.verification_digest,
          policy_version: verification.policy_version,
          evidence_status: verification.evidence_status,
          recorded_at: verification.recorded_at,
          source: source_evidence_from_event(event, occurred_at: verification.recorded_at)
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
        evidence = values.fetch(:evidence)
        ReleaseSetVerificationViewV1.new(
          **values,
          integration_events: values.fetch(:integration_events).map { Coordinator::Write::EventReference.new(_1) },
          evidence: verification_evidence_value(evidence),
          source: source_evidence_value(values.fetch(:source))
        )
      end

      def event_reference_value(attributes)
        Coordinator::Write::EventReference.new(attributes) if attributes
      end

      def integration_failure_value(attributes)
        return unless attributes

        Coordinator::Write::ReleaseSets::IntegrationFailureV1.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer))
        )
      end

      def verification_evidence_value(attributes)
        Coordinator::Write::ReleaseSets::VerificationEvidenceV1.new(
          **attributes,
          producer: Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(attributes.fetch(:producer)),
          findings: attributes.fetch(:findings).map do |finding|
            Coordinator::Write::ReleaseSets::VerificationFindingV1.new(finding)
          end
        )
      end

      def every_member_integrated?(members, integrations)
        latest = integrations.each_with_object({}) do |integration, result|
          values = symbolize(integration)
          result[values.fetch(:repository_id)] = values.fetch(:outcome)
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

      def source_evidence_from_event(event, occurred_at:)
        ReleaseSetSourceEvidenceV1.new(
          event: event_reference(event),
          actor: actor(event),
          markers: event.markers,
          metadata: event.metadata,
          global_position: event.global_position,
          occurred_at:,
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
          authenticated: false
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
