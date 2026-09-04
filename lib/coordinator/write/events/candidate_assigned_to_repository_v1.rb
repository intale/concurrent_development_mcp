# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateAssignedToRepositoryV1 < Base
      contract type: "CandidateAssignedToRepository", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
    end
  end
end
