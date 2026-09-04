# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAddedToChangeSetV2 < Base
      contract type: "WorkItemAddedToChangeSet", version: 2

      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
    end
  end
end
