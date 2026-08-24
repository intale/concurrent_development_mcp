# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class MemberDigestDocumentV1 < Value
      attribute :candidate_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :manifest_digest, Types::Sha256Digest
      attribute :candidate_event, EventReference
      attribute :manifest_event, EventReference
    end
  end
end
