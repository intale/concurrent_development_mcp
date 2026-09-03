# frozen_string_literal: true

module CommandResultFixture
  module_function

  def project(task_id, event_store:)
    task = Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state
    command = Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(task.command_id)
    terminal = command.persisted_events.last
    return unless command.state.terminal? && terminal

    receipts = Coordinator::Read::Repositories::CommandReceipts.new
    existing = receipts.fetch(command.state.command_id)
    return existing if existing

    result = Coordinator::Read::CommandResults::Assembler.new(event_store:).call(
      Coordinator::Read::CommandResults::SourceLoader.new(event_store:).call(terminal)
    )
    FactoryBot.create(
      :coordinator_read_command_receipt,
      command_id: command.state.command_id,
      request_id: result.command_id,
      command_stream_revision: terminal.stream_revision,
      tool_name: result.tool_name,
      canonical_input_digest: result.canonical_input_digest,
      status: result.status,
      summary: result.summary,
      receipt: result.receipt,
      completion: result.to_h,
      completed_at_domain: result.completed_at,
      created_at: terminal.created_at,
      updated_at: terminal.created_at
    )
    result
  end
end
