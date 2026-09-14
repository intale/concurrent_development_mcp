# frozen_string_literal: true

module CommandTraceFixture
  module_function

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
