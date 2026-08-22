# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class CoordinationTaskExecutor
      INTERNAL_ERROR = Coordinator::Write::Tasks::JsonRpcErrorV1.new(
        code: -32_603,
        message: "Internal error"
      )

      def initialize(
        event_store:,
        source_builder: CoordinationTaskSourceBuilder.new,
        task_loader: Coordinator::Write::Tasks::Loader.new(event_store:),
        transition: Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(
          event_store:,
          loader: task_loader
        ),
        start_task: Coordinator::Write::Operations::StartCoordinationTask.new(transition:),
        record_outcome: Coordinator::Write::Operations::RecordCoordinationTaskOutcome.new(transition:),
        target_command_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        target_executor: Coordinator::Write::Tasks::TargetExecutor.new(event_store:),
        tool_result_mapper: Coordinator::Write::Tasks::ToolResultMapper.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @source_builder = source_builder
        @task_loader = task_loader
        @start_task = start_task
        @record_outcome = record_outcome
        @target_command_builder = target_command_builder
        @target_executor = target_executor
        @tool_result_mapper = tool_result_mapper
        @stream_factory = stream_factory
      end

      def call(event)
        source = @source_builder.call(event)
        started_state = transition_value!(
          @start_task.call(task_id: source.payload.task_id, caused_by: source.event),
          transition: "start"
        )
        return nil if started_state.terminal?

        started_event = execution_started_event(source.payload.task_id)
        command = @target_command_builder.call(source.payload.command_input)
        outcome, parent_event = execute_target(command, started_event:)
        transition_value!(
          @record_outcome.call(
            task_id: source.payload.task_id,
            outcome:,
            caused_by: parent_event
          ),
          transition: "outcome"
        )

        nil
      end

      private

      def execution_started_event(task_id)
        event = @task_loader.call(task_id).persisted_events.find do |persisted|
          persisted.type == "CoordinationTaskExecutionStarted"
        end
        return event if event

        raise CoordinationTaskExecutionRejected,
              "Task #{task_id} is nonterminal without a persisted execution-started event"
      end

      def execute_target(command, started_event:)
        result = @target_executor.call(command, caused_by: started_event)
        tool_result = @tool_result_mapper.call(result, command_id: command.command_id)
        parent_event = outcome_parent_event(result, command:, started_event:)

        [ Coordinator::Write::Tasks::OutcomeV1::Completed.new(result: tool_result), parent_event ]
      rescue StandardError => error
        Rails.error.report(error, handled: true)
        [ Coordinator::Write::Tasks::OutcomeV1::Failed.new(error: INTERNAL_ERROR), started_event ]
      end

      def command_completion_event(command_id)
        @event_store.read(
          @stream_factory.command(command_id),
          Coordinator::Write::EventQueries::COMMAND_COMPLETION
        ).sole
      end

      def outcome_parent_event(result, command:, started_event:)
        return started_event if result.failure?

        completion_parent_event(command.command_id, started_event:)
      end

      def completion_parent_event(command_id, started_event:)
        completion = command_completion_event(command_id)
        return completion if completion.causation_id == started_event.id

        started_event
      end

      def transition_value!(result, transition:)
        return result.value! if result.success?

        failure = result.failure
        raise CoordinationTaskExecutionRejected,
              "Task #{transition} rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
