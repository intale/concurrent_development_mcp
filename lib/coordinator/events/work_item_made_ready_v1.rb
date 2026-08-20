# frozen_string_literal: true

module Coordinator
  module Events
    class WorkItemMadeReadyV1 < Base
      contract type: "WorkItemMadeReady", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :readiness_decision_id, Types::Identifier
      attribute :reason, Types::String.enum("change_set_activated")
      attribute :made_ready_at, Types::Timestamp
    end
  end
end
