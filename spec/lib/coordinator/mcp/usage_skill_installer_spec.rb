# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::UsageSkills::Installer, :event_store do
  it "publishes through a durable Task and finishes independently of read projections" do
    output = StringIO.new
    definition = Coordinator::Mcp::UsageSkills::Catalog.all.first
    installer = described_class.new(
      server: Coordinator::Container["mcp.server"], definitions: [ definition ], output:, timeout_seconds: 15
    )
    worker = Thread.new { installer.call }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    task_id = nil
    until task_id
      task_id = output.string[/Task ([0-9a-f-]{36})/, 1]
      raise "Installer did not submit a Task: #{output.string}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01 unless task_id
    end

    event_store = Coordinator::Write::EventStore.new(client: PgEventstore.client)
    stream = Coordinator::Write::StreamFactory.new.coordination_task(task_id)
    submitted = event_store.read(stream, Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
      .find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    raise "Installer did not finish" unless worker.join(10)

    result = worker.value.sole
    expect(result.to_h).to include(name: definition.name, revision: 1, outcome: "published", task_id:)
    expect(Coordinator::Read::Skill.count).to eq(0)
  ensure
    worker&.kill if worker&.alive?
    worker&.join
  end

  it "reports a pending handle without cancelling or assuming rollback when workers are stopped" do
    installer = described_class.new(
      server: Coordinator::Container["mcp.server"],
      definitions: Coordinator::Mcp::UsageSkills::Catalog.all.take(1), output: StringIO.new, timeout_seconds: 0
    )
    task_id = nil
    expect { installer.call }.to raise_error(Coordinator::Mcp::UsageSkills::InstallError) do |error|
      task_id = error.task_id
      expect(error.message).to include("still working", "Nothing was cancelled or rolled back", "MCP_USAGE_SKILL_RUN_ID=")
    end
    result = Coordinator::Container["mcp.tasks.lifecycle"].get(taskId: task_id)
    expect(result.status).to eq("working")
  end
end
