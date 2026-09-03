# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordGuidance, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:guidance_events) do
    Coordinator::Write::EventReadCriteria.new(
      event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
      maximum_count: 10,
      direction: :asc
    )
  end
  let(:input) do
    {
      command_id: "cmd-guidance-1",
      actor: { kind: "agent", id: "host-1" },
      message_id: "M-1",
      conversation_id: "C-1",
      source: "mcp_client",
      text: "Do not use Redis in billing.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: "CS-1",
        work_item_id: nil,
        attempt_id: nil
      }
    }
  end

  it "atomically persists direct evidence and returns a non-normative result" do
    result = operation.call(input)

    expect(result).to be_success
    fact = conversation_events("C-1").sole
    expect(fact).to have_attributes(type: "UserUtteranceRecorded", stream_revision: 0)
    expect(fact.markers).to include("message:M-1", "conversation:C-1", "command:cmd-guidance-1")
    expect(fact.data).to include(
      "message_id" => "M-1",
      "conversation_id" => "C-1",
      "source" => "mcp_client",
      "text" => "Do not use Redis in billing."
    )
    expect(fact.metadata).to include("actor_kind" => "agent", "actor_id" => "host-1")
    expect(result.value!.data).to eq(
      Coordinator::Write::CommandReceiptData::Guidance.new(
        message_id: "M-1",
        conversation_id: "C-1",
        source: "mcp_client",
        policy_status: "evidence_only",
        recorded_at: fact.data.fetch("recorded_at")
      )
    )
    expect(command_events("cmd-guidance-1")).to be_empty
  end

  it "persists forwarded evidence under the same strict message boundary" do
    result = operation.call(
      input.merge(command_id: "cmd-guidance-2", message_id: "M-2", source: "agent_forwarded")
    )

    expect(result).to be_success
    expect(conversation_events("C-1").sole.type).to eq("UserUtteranceForwardedByAgent")
  end

  it "leaves replay ownership to the registered Command lifecycle" do
    expect(operation.call(input)).to be_success
    original_ids = conversation_events("C-1").map(&:id) + command_events("cmd-guidance-1").map(&:id)

    replay = operation.call(input)

    expect(replay.failure.code).to eq(:message_already_recorded)
    expect(conversation_events("C-1").map(&:id) + command_events("cmd-guidance-1").map(&:id)).to eq(original_ids)
  end

  it "rejects the same global message ID in another conversation and source mode" do
    operation.call(input)

    result = operation.call(
      input.merge(
        command_id: "cmd-guidance-duplicate",
        conversation_id: "C-2",
        source: "agent_forwarded"
      )
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:message_already_recorded)
    expect(conversation_events("C-2")).to be_empty
    expect(command_events("cmd-guidance-duplicate")).to be_empty
  end

  it "serializes concurrent claims of one message across different Conversation streams" do
    inputs = [
      input.merge(command_id: "cmd-guidance-race-1", conversation_id: "C-race-1"),
      input.merge(
        command_id: "cmd-guidance-race-2",
        conversation_id: "C-race-2",
        source: "agent_forwarded"
      )
    ]

    results = inputs.map do |competing_input|
      Thread.new { described_class.new(event_store:).call(competing_input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:message_already_recorded)
    expect(global_message_events("M-1").length).to eq(1)
    expect(inputs.flat_map { command_events(_1.fetch(:command_id)) }).to be_empty
  end

  def conversation_events(conversation_id)
    event_store.read(streams.conversation(conversation_id), guidance_events)
  end

  def global_message_events(message_id)
    event_store.read_global_marked(
      Coordinator::Write::EventQueries.guidance_message("message:#{message_id}")
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end
end
