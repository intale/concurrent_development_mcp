# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class MergeAuthorizations
      include EventTimestamped

      def latest_for(merge_snapshot_id)
        record = Coordinator::Read::MergeAuthorization
          .where(merge_snapshot_id:)
          .order(source_global_position: :desc)
          .first
        record && build_view(record)
      end

      def store(event:, decision:)
        create_from_event(Coordinator::Read::MergeAuthorization, event:, attributes: {
          authorization_id: decision.authorization_id,
          merge_snapshot_id: decision.merge_snapshot_id,
          outcome: outcome(decision),
          policy_version: event.metadata.fetch("policy_version"),
          snapshot_binding: decision.snapshot_binding.to_h,
          expected_impact_policy: event.metadata["expected_impact_policy"],
          evaluation: decision.evaluation.to_h,
          input_digest: event.metadata.fetch("input_digest"),
          decision_digest: event.metadata.fetch("decision_digest"),
          decided_at_domain: event.created_at,
          source_event: event_reference(event).to_h,
          source_actor: actor(event).to_h,
          source_markers: event.markers,
          source_metadata: event.metadata,
          source_causation_id: event.causation_id,
          source_correlation_id: event.correlation_id,
          source_global_position: event.global_position,
          source_persisted_at: event.created_at
        })
      end

      private

      def build_view(record)
        expected_policy = record.expected_impact_policy
        MergeAuthorizationViewV1.new(
          authorization_id: record.authorization_id,
          merge_snapshot_id: record.merge_snapshot_id,
          outcome: record.outcome,
          policy_version: record.policy_version,
          snapshot_binding: Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
            symbolize(record.snapshot_binding)
          ),
          expected_impact_policy: expected_policy &&
            Coordinator::Write::MergeAuthorizations::ExpectedImpactPolicyV1.new(
              symbolize(expected_policy)
            ),
          evaluation: Coordinator::Write::MergeAuthorizations::EvaluationV1.new(
            symbolize(record.evaluation)
          ),
          input_digest: record.input_digest,
          decision_digest: record.decision_digest,
          decided_at: record.decided_at_domain.utc.iso8601(6),
          source: source(record)
        )
      end

      def source(record)
        MergeSnapshotSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.source_event)),
          actor: AttributedActorV1.new(symbolize(record.source_actor)),
          markers: record.source_markers,
          metadata: record.source_metadata,
          global_position: record.source_global_position,
          occurred_at: record.decided_at_domain.utc.iso8601(6),
          persisted_at: record.source_persisted_at.utc.iso8601(6),
          causation_id: record.source_causation_id,
          correlation_id: record.source_correlation_id
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

      def outcome(decision)
        decision.is_a?(Coordinator::Write::Events::MergeAuthorizationGrantedV2) ? "granted" : "denied"
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
