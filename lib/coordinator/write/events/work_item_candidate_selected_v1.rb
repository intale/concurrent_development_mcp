# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCandidateSelectedV1 < Base
      contract type: "WorkItemCandidateSelected", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :selected_at, Types::Timestamp
    end
  end
end
