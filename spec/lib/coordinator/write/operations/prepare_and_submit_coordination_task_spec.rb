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
    expect(events.sole.metadata.fetch("command_id")).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(events.sole.markers).to include(
      Coordinator::Write::Tasks::ExecutionLane.new.marker(task_id)
    )
    registration = event_store.read(
      streams.command(result.value!.command_id),
      Coordinator::Write::EventQueries::COMMAND_REGISTRATION
    ).sole
    expect(registration.data).to include(
      "command_id" => result.value!.command_id,
      "request_id" => "cmd-public-create",
      "tool_name" => "change_set_create"
    )
  end

  it "returns the existing Task when the same actor replays the same request and input" do
    first = operation.call(input(command_id: "cmd-public-replay"))
    replay = operation.call(input(command_id: "cmd-public-replay"))

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!).to have_attributes(
      task_id: first.value!.task_id,
      command_id: first.value!.command_id
    )
    expect(task_events(first.value!.task_id).length).to eq(1)
  end

  it "rejects reuse of an actor request ID with different canonical input" do
    first = operation.call(input(command_id: "cmd-public-conflict"))
    conflicting = operation.call(
      input(command_id: "cmd-public-conflict").merge(goal: "A different requested outcome")
    )

    expect(first).to be_success
    expect(conflicting).to be_failure
    expect(conflicting.failure).to have_attributes(code: :command_id_reused)
    expect(task_events(first.value!.task_id).length).to eq(1)
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
    expect(command_registrations(command_id)).to be_empty
  end


  it "rejects coordinator-owned UUIDv7 command identities before allocating a Task" do
    command_id = SecureRandom.uuid_v7

    result = operation.call(input(command_id:))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_input)
    expect(command_registrations(command_id)).to be_empty
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

  def command_registrations(request_id)
    marker = Coordinator::Shared::CompoundMarkerBuilder.new.call(
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "command-request",
        components: [
          "actor-kind:agent",
          "actor-id:agent-a",
          "request-id:#{request_id}"
        ]
      )
    ).marker
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorControl",
        stream_name: "Command",
        event_types: [ "CommandRegistered" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end
end
