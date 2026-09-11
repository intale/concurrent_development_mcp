# frozen_string_literal: true

module Coordinator::Read
  class WorkItemCompletionViewV1 < Value
    attribute :work_item_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :attempt_id, Types::Identifier
    attribute :candidate_id, Types::Identifier
    attribute :candidate_event, Coordinator::Write::EventReference
    attribute :produced_outputs, Types::Array.of(Coordinator::Write::WorkItemOutputV1)
    attribute :completed_at, Types::Timestamp
  end
end
