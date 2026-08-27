# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class OperationBatchRunner
      HANDLED_CODES = %i[
        operation_batch_terminal
        operation_batch_item_already_recorded
        operation_batch_cancellation_pending
      ].freeze

      def initialize(
        event_store:,
        source_builder: OperationBatches::SourceBuilder.new,
        loader: Coordinator::Write::OperationBatches::Loader.new(event_store:),
        target_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        target_executor: Coordinator::Write::Tasks::TargetExecutor.new(event_store:),
        result_mapper: Coordinator::Write::Tasks::ToolResultMapper.new,
        completion_loader: OperationBatches::TargetCompletionLoader.new(event_store:),
        command_builder: OperationBatches::CommandBuilder.new,
        batch_executor: Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:)
      )
        @source_builder = source_builder
        @loader = loader
        @target_builder = target_builder
        @target_executor = target_executor
        @result_mapper = result_mapper
        @completion_loader = completion_loader
        @command_builder = command_builder
        @batch_executor = batch_executor
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::OperationBatchCreatedV1,
             Coordinator::Write::Events::OperationBatchContinuationRequestedV1
          process_page(source)
        when Coordinator::Write::Events::OperationBatchCancellationRequestedV1
          complete_cancellation(source)
        end
        nil
      end

      private

      def process_page(source)
        instrument_page_boundary("operation_batch_page_start", source)
        bounds(source).each do |index|
          snapshot = @loader.call(source.payload.batch_id)
          return if snapshot.state.terminal
          return complete_observed_cancellation(snapshot) if snapshot.state.cancellation
          next if snapshot.state.outcome(index)

          item = snapshot.state.item(index)
          next unless item

          execute_item(source:, item:)
        end

        progress_after_page(source)
        instrument_page_boundary("operation_batch_page", source)
      end

      def execute_item(source:, item:)
        command = @target_builder.call(item.command_input)
        target_result = @target_executor.call(command, caused_by: source.event)
        public_result = @result_mapper.call(target_result, command_id: command.command_id)
        completion = target_result.success? ? @completion_loader.call(command.command_id) : nil
        caused_by = completion&.event || source.event
        execute!(
          @batch_executor.call_command(
            @command_builder.record_outcome(
              source:,
              item:,
              result: public_result,
              completion:
            ),
            caused_by:
          )
        )
      end

      def progress_after_page(source)
        snapshot = @loader.call(source.payload.batch_id)
        return if snapshot.state.terminal
        return complete_observed_cancellation(snapshot) if snapshot.state.cancellation

        pending = snapshot.state.pending_indexes
        if pending.empty?
          execute!(@batch_executor.call_command(@command_builder.complete(source:), caused_by: source.event))
          return
        end

        page_start = pending.min
        page_end = [
          page_start + snapshot.state.creation.page_size - 1,
          snapshot.state.creation.total - 1
        ].min
        execute!(
          @batch_executor.call_command(
            @command_builder.continuation(source:, page_start:, page_end:),
            caused_by: source.event
          )
        )
      end

      def complete_observed_cancellation(snapshot)
        event = snapshot.physical_events.reverse.find do |physical|
          physical.type == "OperationBatchCancellationRequested"
        end
        complete_cancellation(@source_builder.call(event))
      end

      def complete_cancellation(source)
        execute!(
          @batch_executor.call_command(
            @command_builder.complete_cancellation(source:),
            caused_by: source.event
          )
        )
      end

      def bounds(source)
        payload = source.payload
        if payload.is_a?(Coordinator::Write::Events::OperationBatchCreatedV1)
          0..([ payload.page_size - 1, payload.total - 1 ].min)
        else
          payload.page_start..payload.page_end
        end
      end

      def execute!(result)
        return result.value! if result.success?
        return if HANDLED_CODES.include?(result.failure.code)

        failure = result.failure
        raise OperationBatchProcessRejected,
              "Batch process rejected: #{failure.code} - #{failure.message}"
      end

      def instrument_page_boundary(operation, source)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation:,
          command_id: source.event.metadata.fetch("command_id"),
          batch_id: source.payload.batch_id,
          source_event_id: source.event.id
        )
      end
    end
  end
end
