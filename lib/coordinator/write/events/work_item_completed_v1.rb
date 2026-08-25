# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemCompletedV1 < Base
      Output = WorkItemOutputV1

      contract type: "WorkItemCompleted", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :produced_outputs,
                Types::Array.of(Output).constrained(max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT)
      attribute :rule_version, Types::String.enum("work-item-completion/v1")
      attribute :completed_at, Types::Timestamp
    end
  end
end
