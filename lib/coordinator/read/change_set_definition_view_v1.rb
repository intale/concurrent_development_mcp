# frozen_string_literal: true

module Coordinator::Read
  class ChangeSetDefinitionViewV1 < Value
    attribute :change_set_id, Types::Identifier
    attribute :goal, Types::Goal
    attribute :acceptance_criteria, Types::StateAcceptanceCriteria
    attribute :created_at, Types::Timestamp
  end
end
