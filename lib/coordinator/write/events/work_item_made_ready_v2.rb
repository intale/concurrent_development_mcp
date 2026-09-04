# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemMadeReadyV2 < Base
      contract type: "WorkItemMadeReady", version: 2

      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :readiness_decision_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end
  end
end
