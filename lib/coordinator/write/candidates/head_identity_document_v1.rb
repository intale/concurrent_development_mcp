# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class HeadIdentityDocumentV1 < Value
      SCHEMA = "candidate-head-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid
    end
  end
end
