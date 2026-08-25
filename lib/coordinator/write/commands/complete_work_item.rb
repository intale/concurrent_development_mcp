# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteWorkItem < Value
      Output = Types.Instance(WorkItemOutputV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :produced_outputs,
                Types::Array.of(Output).constrained(max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT)
    end
  end
end
