# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class CandidateCheckpointScopeV1 < Coordinator::Write::Value
    attribute :candidate_id, Coordinator::Write::Types::Identifier
    attribute :change_set_id, Coordinator::Write::Types::Identifier
    attribute :work_item_id, Coordinator::Write::Types::Identifier
    attribute :attempt_id, Coordinator::Write::Types::Identifier
    attribute :repository_id, Coordinator::Write::Types::RepositoryId
  end
end
