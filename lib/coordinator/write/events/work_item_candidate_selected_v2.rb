# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCandidateSelectedV2 < Base
      contract type: "WorkItemCandidateSelected", version: 2

      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
    end
  end
end
