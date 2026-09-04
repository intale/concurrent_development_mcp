# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetGoalDefinedV1 < Base
      contract type: "ChangeSetGoalDefined", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
    end
  end
end
