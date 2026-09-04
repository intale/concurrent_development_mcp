# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCompletedV2 < Base
      contract type: "WorkItemCompleted", version: 2

      attribute :work_item_id, Types::Identifier
    end
  end
end
