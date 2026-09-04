# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCreatedV2 < Base
      contract type: "WorkItemCreated", version: 2

      attribute :work_item_id, Types::Identifier
    end
  end
end
