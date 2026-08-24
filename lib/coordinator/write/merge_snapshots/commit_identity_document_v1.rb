# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CommitIdentityDocumentV1 < Value
      SCHEMA = "merge-snapshot-commit-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :merge_commit_oid, Types::GitOid
    end
  end
end
