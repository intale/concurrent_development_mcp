# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemGoalDefinedV1 < Base
      contract type: "WorkItemGoalDefined", version: 1

      attribute :work_item_id, Types::Identifier
      attribute :goal, Types::Goal
    end
  end
end
