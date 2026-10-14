# frozen_string_literal: true

module Coordinator::Read
  # An immutable assembly of trusted native facts, not a source schema.
  class CandidateSubmissionViewV2 < Data.define(
    :candidate_id, :change_set_id, :work_item_id, :attempt_id, :agent_id, :repository_id,
    :target_branch, :object_format, :base_commit_oid, :head_commit_oid, :checkpoint_kind,
    :intention_set_id, :intentions, :manifest_digest, :build_context_digest, :evidence_status,
    :manifest, :build_context, :created_event, :submitted_event, :manifest_event, :build_context_event
  )
  end
end
