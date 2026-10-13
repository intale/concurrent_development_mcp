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
        target_executor: Coordinator::Processes::TargetCommandExecutor.new(event_store:),
        item_executor: Coordinator::Processes::OperationBatches::ItemExecutor.new(event_store:, target_builder:, target_executor:),
        item_registrar: OperationBatches::ItemRegistrar.new(event_store:),
        command_builder: OperationBatches::CommandBuilder.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        batch_executor: Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:),
        item_failure: Coordinator::Write::Operations::ExecuteRecordOperationBatchItemFailure.new(event_store:),
        task_completer: OperationBatches::TaskCompleter.new(event_store:)
      )
        @source_builder = source_builder
        @event_store = event_store
        @loader = loader
        @item_executor = item_executor
        @item_registrar = item_registrar
        @command_builder = command_builder
        @process_step_planner = process_step_planner
        @batch_executor = batch_executor
        @item_failure = item_failure
        @task_completer = task_completer
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::OperationBatchCreatedV2,
             Coordinator::Write::Events::OperationBatchContinuationRequestedV2
          process_page(source)
        when Coordinator::Write::Events::OperationBatchCancellationRequestedV2
          complete_cancellation(source)
        when Coordinator::Write::Events::OperationBatchCompletedV2, Coordinator::Write::Events::OperationBatchCancelledV2
          @task_completer.call(source.event)
        end
        nil
      end

      private

      def process_page(source)
        instrument_page_boundary("operation_batch_page_start", source)
        initial_snapshot = @loader.call(source.payload.batch_id)
        return if initial_snapshot.state.terminal
        return complete_observed_cancellation(initial_snapshot) if initial_snapshot.state.cancellation
        bounds(source, initial_snapshot.state).each do |index|
          next if initial_snapshot.state.outcome(index)

          result = assign_item(source:, index:)
          if result.failure?
            return progress_after_page(source) if HANDLED_CODES.include?(result.failure.code)
            if result.failure.code == :concurrency_conflict
              record_item_failure(source:, index:, failed_step: "assign-item", error: result.failure, effects_committed: false)
              next
            end
            raise OperationBatchProcessRejected, result.failure.message
          end
          assignment = result.value!
          next unless assignment.assigned?

          instrument_page_boundary("operation_batch_item_assigned", source)
          execute_item(source:, item: assignment.item, assignment_event: assignment.event)
        end

        progress_after_page(source)
        instrument_page_boundary("operation_batch_page", source)
      end

      def assign_item(source:, index:)
        process_step = plan(
          source_event: source.event, step_name: "assign-item-command",
          subject_kind: "operation-batch-item", subject_id: "#{source.payload.batch_id}:#{index}",
          rule_version: "operation-batch-item-assignment/v1"
        )
        result = @item_registrar.call_command(
          @command_builder.assign_item(source:, index:, command_id: process_step.target_command_id),
          caused_by: process_step.event
        )
        if result.failure? && !HANDLED_CODES.include?(result.failure.code)
          @process_step_planner.record_dispatch_failure(process_step:, failure: result.failure)
        end
        result
      end

      def execute_item(source:, item:, assignment_event:)
        start_step = plan(
          source_event: assignment_event, step_name: "start-item-execution",
          subject_kind: "operation-batch-item", subject_id: "#{source.payload.batch_id}:#{item.index}",
          rule_version: "operation-batch-item-start/v1"
        )
        target_result = @item_executor.call(
          command: @command_builder.start_item(source:, item:, command_id: start_step.target_command_id),
          item:, caused_by: start_step.event
        )
        return if target_result.failure? && HANDLED_CODES.include?(target_result.failure.code)

        if target_result.failure?
          @process_step_planner.record_dispatch_failure(process_step: start_step, failure: target_result.failure)
          if target_result.failure.code == :concurrency_conflict
            effects = @event_store.read_command_events(Coordinator::Write::CommandEventReadCriteria.new(
              command_id: item.command_id, through_global_position: Coordinator::Write::EventQueries::RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION,
              maximum_count: Coordinator::Write::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS))
            record_item_failure(source:, index: item.index, failed_step: "start-or-finalize-item", error: target_result.failure, effects_committed: !effects.empty?)
            return
          end
        end
        execution = target_result.value!
        parent = outcome_parent(source, execution)
        process_step = plan(
          source_event: parent,
          step_name: "record-item-outcome",
          subject_kind: "operation-batch-item",
          subject_id: "#{source.payload.batch_id}:#{item.index}",
          rule_version: "operation-batch-item-outcome/v1"
        )
        instrument_page_boundary(
          "operation_batch_item_outcome",
          source,
          process_command_id: process_step.target_command_id
        )
        recorded = @batch_executor.call_command(
            @command_builder.record_outcome(
              source:,
              item:,
              execution:,
              command_id: process_step.target_command_id
            ),
            caused_by: process_step.event
          )
        if recorded.failure? && recorded.failure.code == :concurrency_conflict
          @process_step_planner.record_dispatch_failure(process_step:, failure: recorded.failure)
          record_item_failure(source:, index: item.index, failed_step: "record-item-outcome", error: recorded.failure,
            effects_committed: execution.command_state.succeeded? || execution.command_state.execution_failure&.effects_committed || false)
        else
          execute!(recorded, process_step:)
        end
      end

      def progress_after_page(source)
        snapshot = @loader.call(source.payload.batch_id)
        return if snapshot.state.terminal
        return complete_observed_cancellation(snapshot) if snapshot.state.cancellation

        pending = snapshot.state.pending_indexes
        if pending.empty?
          process_step = plan(
            source_event: source.event,
            step_name: "complete-batch",
            subject_kind: "operation-batch",
            subject_id: source.payload.batch_id,
            rule_version: "operation-batch-completion/v1"
          )
          execute!(
            @batch_executor.call_command(
              @command_builder.complete(source:, command_id: process_step.target_command_id),
              caused_by: process_step.event
            ),
            process_step:
          )
          return
        end

        page_start = pending.min
        page_end = [
          page_start + snapshot.state.processing_page_size - 1,
          snapshot.state.item_count - 1
        ].min
        process_step = plan(
          source_event: source.event,
          step_name: "request-page-continuation",
          subject_kind: "operation-batch-page",
          subject_id: "#{source.payload.batch_id}:#{page_start}",
          rule_version: "operation-batch-continuation/v1"
        )
        execute!(
          @batch_executor.call_command(
            @command_builder.continuation(
              source:,
              page_start:,
              page_end:,
              command_id: process_step.target_command_id
            ),
            caused_by: process_step.event
          ),
          process_step:
        )
      end

      def record_item_failure(source:, index:, failed_step:, error:, effects_committed:)
        step = plan(source_event: source.event, step_name: "record-item-failure",
          subject_kind: "operation-batch-item", subject_id: "#{source.payload.batch_id}:#{index}", rule_version: "operation-batch-item-failure/v1")
        command = Coordinator::Write::Commands::RecordOperationBatchItemFailure.new(command_id: step.target_command_id,
          actor: OperationBatches::CommandBuilder::SYSTEM_ACTOR, batch_id: source.payload.batch_id, index:,
          failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(failed_step:, reason_code: error.code.to_s,
            reason: error.message, retryable: true, effects_committed:, attempts: 3))
        # If the failure fact itself cannot commit after its bounded attempts,
        # leave delivery unacknowledged. Never fabricate a successful outcome.
        @item_failure.call_command(command, caused_by: step.event).value!
      end

      def outcome_parent(source, execution)
        terminal_event = execution.terminal_event
        return source.event unless terminal_event.correlation_id == source.event.correlation_id

        terminal_event
      end

      def complete_observed_cancellation(snapshot)
        event = snapshot.physical_events.reverse.find do |physical|
          physical.type == "OperationBatchCancellationRequested"
        end
        complete_cancellation(@source_builder.call(event))
      end

      def complete_cancellation(source)
        snapshot = @loader.call(source.payload.batch_id)
        return if snapshot.state.terminal

        snapshot.state.started_pending_indexes.each do |index|
          item_snapshot = @loader.item(source.payload.batch_id, index)
          next if item_snapshot.state.outcome(index)

          assignment_event = item_snapshot.physical_events.find { _1.type == "OperationBatchItemCommandAssigned" }
          execute_item(source:, item: item_snapshot.state.item(index), assignment_event:)
        end

        process_step = plan(
          source_event: source.event,
          step_name: "complete-cancellation",
          subject_kind: "operation-batch",
          subject_id: source.payload.batch_id,
          rule_version: "operation-batch-cancellation/v1"
        )
        execute!(
          @batch_executor.call_command(
            @command_builder.complete_cancellation(
              source:,
              command_id: process_step.target_command_id
            ),
            caused_by: process_step.event
          ),
          process_step:
        )
      end

      def bounds(source, state)
        payload = source.payload
        if payload.is_a?(Coordinator::Write::Events::OperationBatchCreatedV2)
          0..([ state.processing_page_size - 1, state.item_count - 1 ].min)
        else
          payload.page_start..payload.page_end
        end
      end

      def execute!(result, process_step:)
        return result.value! if result.success?
        return if HANDLED_CODES.include?(result.failure.code)

        @process_step_planner.record_dispatch_failure(process_step:, failure: result.failure)
        # A failed continuation/completion was not committed. Preserve the
        # failure fact, but do not acknowledge delivery and strand the Saga.
        raise OperationBatchProcessRejected, result.failure.message
      end

      def plan(source_event:, step_name:, subject_kind:, subject_id:, rule_version:)
        @process_step_planner.call(
          source_event:,
          process_name: "operation-batch-runner",
          step_name:,
          subject_kind:,
          subject_id:,
          rule_version:,
          allocate_target_entity: false
        )
      end

      def instrument_page_boundary(operation, source, process_command_id: nil)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation:,
          command_id: source.event.metadata.fetch("command_id"),
          process_command_id:,
          batch_id: source.payload.batch_id,
          source_event_id: source.event.id
        )
      end
    end
  end
end
