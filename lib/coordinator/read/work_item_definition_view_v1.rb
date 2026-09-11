# frozen_string_literal: true

module Coordinator::Read
  class WorkItemDefinitionViewV1 < Value
    attribute :work_item_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :repository_id, Types::RepositoryId
    attribute :goal, Types::Goal
    attribute :acceptance_criteria, Types::WorkItemStateAcceptanceCriteria
    attribute :competitive_mode, Types::Strict::Bool
    attribute :created_at, Types::Timestamp
  end
end
