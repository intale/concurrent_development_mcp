# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptCompletedV1 < Base
      contract type: "AttemptCompleted", version: 1

      attribute :attempt_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :completed_at, Types::Timestamp
    end
  end
end
