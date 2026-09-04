# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotCommitRegisteredV2 < Base
      contract type: "MergeSnapshotCommitRegistered", version: 2

      attribute :registry_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :merge_commit_oid, Types::GitOid
    end
  end
end
