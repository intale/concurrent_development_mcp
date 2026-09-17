# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MergeSnapshotMigrationContextV1 < Value
      CandidateContext = Types.Instance(CandidateContextV1)

      attribute :source_registration, Events::MergeSnapshotRegisteredV1
      attribute :source_registration_event, Types.Instance(PgEventstore::Event)
      attribute? :target_registration_event, EventReference.optional.default(nil)
      attribute :snapshot_stream, StreamReference
      attribute :merge_snapshot_id, Types::UuidV7
      attribute :repository_id, Types::UuidV7
      attribute :candidate_contexts,
                Types::Array.of(CandidateContext)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :target_candidate_members,
                Types::Array.of(MergeSnapshots::CandidateMemberV1)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)

      def ordered_candidate_ids
        candidate_contexts.map(&:candidate_id)
      end

      def source_registration_reference
        EventReference.new(
          event_id: source_registration_event.id,
          type: source_registration_event.type,
          stream_context: source_registration_event.stream.context,
          stream_name: source_registration_event.stream.stream_name,
          stream_id: source_registration_event.stream.stream_id,
          stream_revision: source_registration_event.stream_revision
        )
      end

      def target_state(snapshot_digest:)
        MergeSnapshots::StateV2.new(
          merge_snapshot_id:,
          repository_id:,
          target_branch: source_registration.target_branch,
          object_format: source_registration.object_format,
          target_base_commit_oid: source_registration.target_base_commit_oid,
          merge_commit_oid: source_registration.merge_commit_oid,
          ordered_candidates: target_candidate_members,
          producer: source_registration.producer.name,
          run_id: source_registration.run_id,
          produced_at: source_registration.produced_at,
          snapshot_digest:,
          registration_event: target_registration_event!
        )
      end

      def target_registration_event!
        target_registration_event || raise(KeyError, "target MergeSnapshot registration reference is absent")
      end

      def source_state_matches?(state)
        source = source_registration
        state.registration_event == source_registration_reference &&
          [
            state.merge_snapshot_id,
            state.repository_id,
            state.target_branch,
            state.object_format,
            state.target_base_commit_oid,
            state.merge_commit_oid,
            state.producer,
            state.run_id,
            state.produced_at,
            state.snapshot_digest
          ] == [
            source.merge_snapshot_id,
            source.repository_id,
            source.target_branch,
            source.object_format,
            source.target_base_commit_oid,
            source.merge_commit_oid,
            source.producer.name,
            source.run_id,
            source.produced_at,
            source.snapshot_digest
          ] &&
          state.ordered_candidates.map(&:to_h) == source.ordered_candidates.map(&:to_h)
      end

      def markers
        [
          "merge-snapshot:#{merge_snapshot_id}",
          "repository:#{repository_id}",
          "target-branch:#{source_registration.target_branch}",
          "target-base-commit-oid:#{source_registration.target_base_commit_oid}",
          "merge-commit-oid:#{source_registration.merge_commit_oid}"
        ] + ordered_candidate_ids.map { "candidate:#{_1}" }
      end
    end
  end
end
