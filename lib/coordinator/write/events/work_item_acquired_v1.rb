# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAcquiredV1 < Base
      contract type: "WorkItemAcquired", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :acquired_at, Types::Timestamp
    end
  end
end
