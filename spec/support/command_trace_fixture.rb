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
end
