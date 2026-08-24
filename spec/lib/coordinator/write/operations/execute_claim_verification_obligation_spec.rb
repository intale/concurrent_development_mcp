# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteClaimVerificationObligation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:input) do
    {
      command_id: "cmd-claim-1",
      actor: { kind: "agent", id: "agent-blue" },
      obligation_id: obligation_id,
      claim_duration_seconds: 300
    }
  end

  it "VER-CLAIM-SUCCESS-01 atomically persists a fenced claim and its exact receipt" do
    created = create_obligation("claim-success")

    result = Timecop.freeze(Time.utc(2026, 8, 24, 7, 0, 0)) { operation.call(input) }

    expect(result).to be_success
    claim = claim_events.sole
    expect(claim).to have_attributes(type: "VerificationObligationClaimed", stream_revision: 1)
    expect(claim.data).to include(
      "obligation_id" => obligation_id,
      "claimant_id" => "agent-blue",
      "fencing_token" => 1,
      "claimed_at" => "2026-08-24T07:00:00.000000Z",
      "expires_at" => "2026-08-24T07:05:00.000000Z"
    )
    expect(claim.data.fetch("obligation_event")).to eq(event_reference(created.fetch(:event)))
    expect(claim.markers).to include(
      "verification-obligation:#{obligation_id}",
      "claim:#{claim.data.fetch('claim_id')}",
      "claimant:agent-blue",
      "command:cmd-claim-1"
    )
    expect(claim.metadata).to include(
      "actor_kind" => "agent",
      "actor_id" => "agent-blue",
      "policy_version" => "verification-obligation-claim/v1"
    )
    expect(claim.metadata).not_to have_key("correlation_id")
    expect(result.value!.data).to have_attributes(
      obligation_id:,
      claim_id: claim.data.fetch("claim_id"),
      claimant_id: "agent-blue",
      fencing_token: 1,
      claim_event: have_attributes(event_id: claim.id, stream_revision: 1)
    )
    expect(command_events("cmd-claim-1").length).to eq(1)
  end

  it "VER-CLAIM-REPLAY-05 replays exact input and rejects changed command-ID reuse" do
    create_obligation("claim-replay")
    original = operation.call(input)
    event_ids = claim_events.map(&:id) + command_events("cmd-claim-1").map(&:id)

    replay = operation.call(input)
    reused = operation.call(input.merge(claim_duration_seconds: 301))

    expect(replay.value!).to eq(original.value!)
    expect(reused.failure.code).to eq(:command_id_reused)
    expect(claim_events.map(&:id) + command_events("cmd-claim-1").map(&:id)).to eq(event_ids)
  end

  it "VER-CLAIM-NOT-FOUND-07 returns a typed zero-fact denial" do
    @obligation_id = "missing-obligation"

    result = operation.call(input)

    expect(result.failure.code).to eq(:verification_obligation_not_found)
    expect(claim_events).to be_empty
    expect(command_events("cmd-claim-1")).to be_empty
  end

  it "VER-CLAIM-ACTIVE-02 denies an active contender and reclaims at exact expiry with token 2" do
    create_obligation("claim-expiry")
    Timecop.freeze(Time.utc(2026, 8, 24, 7, 0, 0)) { operation.call(input).value! }
    contender = input.merge(command_id: "cmd-claim-2", actor: { kind: "agent", id: "agent-green" })

    active = Timecop.freeze(Time.utc(2026, 8, 24, 7, 4, 59, 999_999)) do
      operation.call(contender)
    end
    reclaimed = Timecop.freeze(Time.utc(2026, 8, 24, 7, 5, 0)) do
      operation.call(contender)
    end

    expect(active.failure.to_h).to include(
      code: :verification_obligation_already_claimed,
      details: include(claimant_id: "agent-blue", fencing_token: 1)
    )
    expect(reclaimed).to be_success
    expect(claim_events.map { _1.data.values_at("claimant_id", "fencing_token") }).to eq(
      [ [ "agent-blue", 1 ], [ "agent-green", 2 ] ]
    )
    expect(command_events("cmd-claim-2").length).to eq(1)
  end

  it "VER-CLAIM-RACE-04 serializes two contenders so exactly one receives token 1" do
    create_obligation("claim-race")
    contenders = [
      input.merge(command_id: "cmd-race-blue"),
      input.merge(command_id: "cmd-race-green", actor: { kind: "agent", id: "agent-green" })
    ]

    results = contenders.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:verification_obligation_already_claimed)
    expect(claim_events.length).to eq(1)
    expect(claim_events.sole.data.fetch("fencing_token")).to eq(1)
    expect(contenders.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
  end

  def create_obligation(prefix)
    created = CandidateObligationScenario.create_obligation(prefix:)
    @obligation_id = created.fetch(:result).obligation_id
    created
  end

  def obligation_id
    @obligation_id
  end

  def claim_events
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationClaimed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def event_reference(event)
    {
      "event_id" => event.id,
      "type" => event.type,
      "stream_context" => event.stream.context,
      "stream_name" => event.stream.stream_name,
      "stream_id" => event.stream.stream_id,
      "stream_revision" => event.stream_revision
    }
  end
end
