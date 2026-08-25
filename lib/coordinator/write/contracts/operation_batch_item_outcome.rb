# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class OperationBatchItemOutcome < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::RecordOperationBatchItemOutcome))
        required(:item).value(Types.Instance(OperationBatches::ItemV1))
        optional(:completion).maybe(Types.Instance(Events::CommandCompletedV1))
        optional(:physical_completion).maybe(:any)
      end

      rule(:command, :item) do
        command = values[:command]
        item = values[:item]
        matches = command.item_command_id == item.command_input.command_id &&
                  command.canonical_input_digest == item.canonical_input_digest
        base.failure("outcome identity must match the manifest item") unless matches
      end

      rule(:command, :item, :completion, :physical_completion) do
        command = values[:command]
        item = values[:item]
        completion = values[:completion]
        physical = values[:physical_completion]

        if command.result.is_error
          if command.target_completion || completion || physical
            base.failure("a rejected result must not cite a target completion")
          end
          next
        end

        unless command.target_completion && completion && physical
          base.failure("a successful result must cite its exact target completion")
          next
        end

        matches = completion.command_id == item.command_input.command_id &&
                  completion.tool_name == item.command_input.tool_name &&
                  completion.canonical_input_digest == item.canonical_input_digest &&
                  completion.status == "ok"
        base.failure("target completion does not match the manifest item") unless matches

        reference = command.target_completion
        exact_physical = physical.id == reference.event_id &&
                         physical.type == reference.type &&
                         physical.stream.context == reference.stream_context &&
                         physical.stream.stream_name == reference.stream_name &&
                         physical.stream.stream_id == reference.stream_id &&
                         physical.stream_revision == reference.stream_revision
        base.failure("target completion reference is not exact") unless exact_physical
      end
    end
  end
end
