# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Guidance::Record do
  subject(:decider) { described_class.new }

  let(:occurred_at) { "2026-08-22T14:30:00.000000Z" }
  let(:anchors) do
    Coordinator::Write::GuidanceAnchorsV1.new(
      repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
      change_set_id: "CS-1",
      work_item_id: nil,
      attempt_id: nil
    )
  end

  def command(source: "mcp_client")
    Coordinator::Write::Commands::RecordGuidance.new(
      command_id: "cmd-guidance-1",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "host-1"),
      message_id: "M-1",
      conversation_id: "C-1",
      source:,
      text: "Do not use Redis in billing.",
      anchors:
    )
  end

  it "implements GDN-01-DIRECT-01 as one utterance and separate anchor facts" do
    result = decider.call(
      state: Coordinator::Write::Domain::Guidance::State.initial,
      command: command,
      occurred_at:
    )

    expect(result).to be_success
    expect(result.value!.writes.map(&:stream).uniq.sole.to_h).to eq(
      context: "HumanGuidance",
      stream_name: "Conversation",
      stream_id: "C-1"
    )
    expect(result.value!.events.first).to eq(
      Coordinator::Write::Events::UserUtteranceRecordedV2.new(
        message_id: "M-1",
        conversation_id: "C-1",
        source: "user",
        text: "Do not use Redis in billing."
      )
    )
    expect(result.value!.events.drop(1)).to contain_exactly(
      Coordinator::Write::Events::GuidanceMessageAnchoredV1.new(
        conversation_id: "C-1", message_id: "M-1", anchor_kind: "repository",
        anchor_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
      ),
      Coordinator::Write::Events::GuidanceMessageAnchoredV1.new(
        conversation_id: "C-1", message_id: "M-1", anchor_kind: "change_set", anchor_id: "CS-1"
      )
    )
  end

  it "implements GDN-01-FORWARDED-01 with a distinct attributed evidence type" do
    result = decider.call(
      state: Coordinator::Write::Domain::Guidance::State.initial,
      command: command(source: "agent_forwarded"),
      occurred_at:
    )

    expect(result.value!.events.first).to be_a(
      Coordinator::Write::Events::UserUtteranceForwardedByAgentV2
    )
    expect(result.value!.events.first.source).to eq("agent_forwarded")
    expect(result.value!.events.drop(1)).to all(be_a(Coordinator::Write::Events::GuidanceMessageAnchoredV1))
  end

  it "implements GDN-01-DUPLICATE-01 as a zero-event failure" do
    first = decider.call(
      state: Coordinator::Write::Domain::Guidance::State.initial,
      command: command,
      occurred_at:
    ).value!.events
    state = Coordinator::Write::Domain::Guidance::State.reduce(first)

    result = decider.call(state:, command: command(source: "agent_forwarded"), occurred_at:)

    expect(result).to be_failure
    expect(result.failure).to eq(
      Coordinator::Write::OutcomeError.new(
        code: :message_already_recorded,
        message: "Guidance message is already recorded",
        details: { message_id: "M-1" }
      )
    )
  end
end
