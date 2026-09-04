# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class SnapshotDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(command:, candidates:)
        document = SnapshotDigestDocumentV1.new(
          schema: SnapshotDigestDocumentV1::SCHEMA,
          merge_snapshot_id: command.merge_snapshot_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          target_base_commit_oid: command.target_base_commit_oid,
          ordered_candidates: candidates.map { member_document(_1) },
          merge_commit_oid: command.merge_commit_oid,
          producer: command.producer,
          run_id: command.run_id,
          produced_at: command.produced_at,
          policy_version: command.policy_version
        )

        @canonical_json.sha256(document.to_h)
      end

      private

      def member_document(history)
        member = history.candidate
        MemberDigestDocumentV1.new(
          candidate_id: member.candidate_id,
          change_set_id: member.change_set_id,
          work_item_id: member.work_item_id,
          attempt_id: member.attempt_id,
          base_commit_oid: member.base_commit_oid,
          head_commit_oid: member.head_commit_oid,
          manifest_digest: member.manifest_digest,
          candidate_event: history.candidate_event,
          manifest_event: history.manifest_event
        )
      end
    end
  end
end
