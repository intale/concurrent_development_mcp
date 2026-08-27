# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareAndSubmitCoordinationTask, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) do
    described_class.new(
      preparer: Coordinator::Write::Operations::PrepareCreateChangeSet.new,
      submitter: Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:)
    )
  end

  it "allocates a Task for a valid caller-owned command ID" do
    result = operation.call(input(command_id: "cmd-public-create"))

    expect(result).to be_success
    task_id = result.value!.task_id
    events = event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
    expect(events.map(&:type)).to eq([ "CoordinationTaskSubmitted" ])
    expect(events.sole.metadata.fetch("command_id")).to eq("cmd-public-create")
    expect(events.sole.markers).to include(
      Coordinator::Write::Tasks::ExecutionLane.new.marker("cmd-public-create")
    )
  end

  it "rejects the internal namespace before allocating a Task" do
    command_id = "internal:lease-expiry:v1:client-supplied"

    result = operation.call(input(command_id:))

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :invalid_input,
      message: "Public command ID is invalid"
    )
    expect(result.failure.details).to have_key(:command_id)
    expect(task_submissions(command_id)).to be_empty
  end

  def input(command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-PUBLIC-COMMAND",
      goal: "Protect the public command namespace",
      acceptance_criteria: [ "Internal command identities remain system-owned" ]
    }
  end

  def task_submissions(command_id)
    PgEventstore.client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 1,
        filter: {
          event_types: [
            { type: "CoordinationTaskSubmitted", markers: [ "command:#{command_id}" ] }
          ]
        }
      }
    )
  end
end
