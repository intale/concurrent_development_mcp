# frozen_string_literal: true

module CommandTraceFixture
  module_function

  # Direct command fixtures also need their successful producing command fact.
  # This does not run subscriptions or create read models through the write side.
  def record_success(command_id:, event_store:, tool_name:, actor_id: "agent-a")
    metadata = Coordinator::Write::EventMetadata.new(
      command_id:, actor_kind: "agent", actor_id:, recorded_by: "coordinator", policy_version: "command-lifecycle/v1"
    )
    factory = Coordinator::Write::EventFactory.new
    facts = [
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:, request_id: "fixture:#{command_id}", tool_name:
      ),
      Coordinator::Write::Events::CommandSucceededV1.new(command_id:)
    ]
    events = facts.map do |fact|
      factory.build!(event: fact, event_id: SecureRandom.uuid_v7, metadata:, markers: [ "command:#{command_id}" ])
    end
    event_store.append(Coordinator::Write::StreamFactory.new.command(command_id), events)
  end

  def events(task_id, event_store:)
    task = Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state
    event_store.read(
      Coordinator::Write::StreamFactory.new.command(task.command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end

  def terminal(task_id, event_store:)
    events(task_id, event_store:).last
  end

  def domain_events(task_id, event_store:)
    task = Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state
    terminal_event = terminal(task_id, event_store:)
    event_store.read_command_events(
      Coordinator::Write::CommandEventReadCriteria.new(
        command_id: task.command_id,
        through_global_position: terminal_event.global_position,
        maximum_count: Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS
      )
    )
  end
end
