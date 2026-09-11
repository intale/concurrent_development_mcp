# frozen_string_literal: true

module Coordinator::Read
  class AttemptCompletionViewV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :candidate_id, Types::Identifier
    attribute :candidate_event, Coordinator::Write::EventReference
    attribute :completed_at, Types::Timestamp
  end
end
