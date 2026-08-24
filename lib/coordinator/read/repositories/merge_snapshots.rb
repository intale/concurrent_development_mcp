# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class MergeSnapshots
      def fetch(merge_snapshot_id)
        record = Coordinator::Read::MergeSnapshot.find_by(merge_snapshot_id:)
        record && build_view(record)
      end

      def store(event:, snapshot:)
        Coordinator::Read::MergeSnapshot.create!(
          merge_snapshot_id: snapshot.merge_snapshot_id,
          repository_id: snapshot.repository_id,
          target_branch: snapshot.target_branch,
          object_format: snapshot.object_format,
          target_base_commit_oid: snapshot.target_base_commit_oid,
          ordered_candidates: snapshot.ordered_candidates.map(&:to_h),
          merge_commit_oid: snapshot.merge_commit_oid,
          producer: snapshot.producer.to_h,
          run_id: snapshot.run_id,
          produced_at_domain: snapshot.produced_at,
          snapshot_digest: snapshot.snapshot_digest,
          policy_version: snapshot.policy_version,
          evidence_status: snapshot.evidence_status,
          registered_at_domain: snapshot.registered_at,
          registered_event: event_reference(event).to_h,
          registered_actor: actor(event).to_h,
          registered_markers: event.markers,
          registered_metadata: event.metadata,
          registered_causation_id: event.causation_id,
          registered_correlation_id: event.correlation_id,
          registered_global_position: event.global_position,
          registered_at_store: event.created_at
        )
      end

      private

      def build_view(record)
        MergeSnapshotViewV1.new(
          merge_snapshot_id: record.merge_snapshot_id,
          repository_id: record.repository_id,
          target_branch: record.target_branch,
          object_format: record.object_format,
          target_base_commit_oid: record.target_base_commit_oid,
          ordered_candidates: record.ordered_candidates.map do |candidate|
            Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(symbolize(candidate))
          end,
          merge_commit_oid: record.merge_commit_oid,
          producer: Coordinator::Write::MergeSnapshots::ProducerV1.new(symbolize(record.producer)),
          run_id: record.run_id,
          produced_at: record.produced_at_domain.utc.iso8601(6),
          snapshot_digest: record.snapshot_digest,
          policy_version: record.policy_version,
          evidence_status: record.evidence_status,
          registered: source_evidence(record)
        )
      end

      def source_evidence(record)
        MergeSnapshotSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.registered_event)),
          actor: AttributedActorV1.new(symbolize(record.registered_actor)),
          markers: record.registered_markers,
          metadata: record.registered_metadata,
          global_position: record.registered_global_position,
          occurred_at: record.registered_at_domain.utc.iso8601(6),
          persisted_at: record.registered_at_store.utc.iso8601(6),
          causation_id: record.registered_causation_id,
          correlation_id: record.registered_correlation_id
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
