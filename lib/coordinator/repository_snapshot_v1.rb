# frozen_string_literal: true

module Coordinator
  class RepositorySnapshotV1 < Value
    attribute :repository_id, Types::RepositoryId
    attribute :object_format, Types::GitObjectFormat
    attribute :commit_oid, Types::GitOid
  end
end
