# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CreateChangeSet < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::AcceptanceCriteria
    end
  end
end
