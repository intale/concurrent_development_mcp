# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class OperationBatchItemOutcome < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::RecordOperationBatchItemOutcome))
        required(:item).value(Types.Instance(OperationBatches::ItemV2))
        required(:command_state).value(Types.Instance(Domain::CommandLifecycles::State))
        required(:physical_target_event).value(:any)
      end

      rule(:command, :item) do
        command = values[:command]
        item = values[:item]
        base.failure("outcome identity must match the Batch item") unless command.item_command_id == item.command_id
      end

      rule(:command, :item, :command_state) do
        command = values[:command]
        item = values[:item]
        state = values[:command_state]
        matches = state.command_id == item.command_id &&
                  state.tool_name == item.command_input.tool_name &&
                  state.canonical_input_digest == item.canonical_input_digest &&
                  state.status == command.outcome
        base.failure("target Command terminal state must match the Batch item outcome") unless matches
      end

      rule(:command, :physical_target_event) do
        reference = values[:command].target_event
        physical = values[:physical_target_event]
        exact = physical &&
                physical.id == reference.event_id &&
                physical.type == reference.type &&
                physical.stream.context == reference.stream_context &&
                physical.stream.stream_name == reference.stream_name &&
                physical.stream.stream_id == reference.stream_id &&
                physical.stream_revision == reference.stream_revision
        base.failure("target Command terminal reference must be exact") unless exact
      end
    end
  end
end
