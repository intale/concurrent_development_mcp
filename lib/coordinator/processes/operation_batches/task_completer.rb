# frozen_string_literal: true

module Coordinator::Processes
  module OperationBatches
    class TaskCompleter
      def initialize(event_store:,
        batch_loader: Coordinator::Write::OperationBatches::Loader.new(event_store:),
        command_loader: Coordinator::Write::CommandLifecycle::Loader.new(event_store:),
        task_source_builder: CoordinationTaskSourceBuilder.new,
        command_transition: Coordinator::Write::Operations::ApplyCommandTransition.new(event_store:),
        task_outcome: Coordinator::Write::Operations::RecordCoordinationTaskOutcome.new(
          transition: Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(event_store:)))
        @event_store, @batch_loader, @command_loader = event_store, batch_loader, command_loader
        @task_source_builder, @command_transition, @task_outcome = task_source_builder, command_transition, task_outcome
      end

      def call(event)
        snapshot = @batch_loader.control(event.stream.stream_id)
        terminal = snapshot.physical_events.find { _1.type == snapshot.state.terminal.class.event_type } if snapshot.state.terminal
        unless terminal && terminal.id == event.id
          raise InvalidSourceEvent, "Batch completion does not match its terminal Saga"
        end
        creation = snapshot.physical_events.find { _1.type == "OperationBatchCreated" }
        command_id = creation.metadata.fetch("command_id")
        submission = @event_store.read_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl", stream_name: "CoordinationTask", event_types: [ "CoordinationTaskSubmitted" ],
          markers: [ "command:#{command_id}" ], maximum_count: 1, direction: :asc
        )).first
        raise InvalidSourceEvent, "Batch has no originating Task instruction" unless submission
        source = @task_source_builder.call(submission)
        document = source.payload.command_input
        input = document.input
        unless input.batch_id == event.stream.stream_id && document.command_id == command_id &&
               input.target_tool == snapshot.state.target_selection.target_tool
          raise InvalidSourceEvent, "Batch terminal refers to a different Task instruction"
        end
        canonical = @command_loader.call(command_id)
        unless canonical.state.tool_name == source.payload.tool_name
          raise InvalidSourceEvent, "Batch terminal refers to a different canonical command"
        end
        unless canonical.state.terminal?
          result = @command_transition.call(
            command: Coordinator::Write::Commands::SucceedCommand.new(command_id:),
            decider: Coordinator::Write::Domain::CommandLifecycles::Succeed.new,
            actor: Coordinator::Write::Commands::Actor.new(kind: input.actor.actor_kind, id: input.actor.actor_id),
            tool_name: source.payload.tool_name, caused_by: event
          )
          result.value!
          canonical = @command_loader.call(command_id)
        end
        @task_outcome.call(task_id: source.payload.task_id,
          outcome: Coordinator::Write::Tasks::OutcomeV3::Completed.new,
          caused_by: canonical.persisted_events.last).value!
        nil
      end
    end
  end
end
