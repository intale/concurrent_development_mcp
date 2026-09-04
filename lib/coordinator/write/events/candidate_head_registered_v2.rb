# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateHeadRegisteredV2 < Base
      contract type: "CandidateHeadRegistered", version: 2

      attribute :registry_id, Types::UuidV7
      attribute :candidate_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid
    end
  end
end
