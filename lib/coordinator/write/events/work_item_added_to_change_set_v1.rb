# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAddedToChangeSetV1 < Base
      contract type: "WorkItemAddedToChangeSet", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :added_at, Types::Timestamp
    end
  end
end
