# frozen_string_literal: true

module Coordinator::Write
  module Events
    class MergeSnapshotCommitRegisteredV1 < Base
      contract type: "MergeSnapshotCommitRegistered", version: 1

      attribute :registry_id, Types::Sha256Digest
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :merge_commit_oid, Types::GitOid
      attribute :snapshot_event, EventReference
      attribute :registered_at, Types::Timestamp
    end
  end
end
