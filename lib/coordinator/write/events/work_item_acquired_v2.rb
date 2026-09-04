# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAcquiredV2 < Base
      contract type: "WorkItemAcquired", version: 2

      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
    end
  end
end
