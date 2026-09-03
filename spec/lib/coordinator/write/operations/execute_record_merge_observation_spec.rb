# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordMergeObservation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:registry) { Coordinator::Write::EventSchemaRegistry.new }

  it "records one exact attributed external transition and leaves replay ownership to the Command lifecycle" do
    registration, authorization, input = scenario("observation-success")

    first = operation.call(input).value!
    replay = operation.call(input)
    physical = observation_event(registration.dig(:input, :merge_snapshot_id))
    payload = load(physical)

    expect(replay.failure.code).to eq(:merge_already_observed)
    expect(payload).to have_attributes(
      authorization_event: authorization.fetch(:completion).data.decision_event,
      target_before_commit_oid: registration.dig(:input, :target_base_commit_oid),
      target_after_commit_oid: registration.dig(:input, :merge_commit_oid),
      evidence_status: "attributed_unverified"
    )
    expect(first.summary).to include("coordinator did not perform or verify it")
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "rejects a result OID that differs from the verified registered snapshot" do
    registration, _authorization, input = scenario("observation-mismatch")
    input[:target_after_commit_oid] = "f" * 40

    result = operation.call(input)

    expect(result.failure.code).to eq(:merge_observation_mismatch)
    expect(observation_events(registration.dig(:input, :merge_snapshot_id))).to be_empty
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "rejects a grant after its Candidate policy partition advances" do
    registration, _authorization, input = scenario("observation-stale")
    change_set_id = load(registration.fetch(:event)).ordered_candidates.sole.change_set_id
    CandidateObligationScenario.activate_policy(
      prefix: "observation-stale",
      change_set_id:,
      level: "merge_gate"
    )

    result = operation.call(input)

    expect(result.failure.code).to eq(:merge_authorization_stale)
    expect(result.failure.details.fetch(:reasons).map { _1.fetch(:code) }).to include(
      "impact_policy_context_stale"
    )
    expect(observation_events(registration.dig(:input, :merge_snapshot_id))).to be_empty
  end

  it "rejects a different Command after the snapshot was observed" do
    registration, _authorization, input = scenario("observation-once")
    operation.call(input).value!

    duplicate = operation.call(input.merge(command_id: "cmd-observe-observation-once-again"))

    expect(duplicate.failure.code).to eq(:merge_already_observed)
    expect(observation_events(registration.dig(:input, :merge_snapshot_id)).length).to eq(1)
  end

  def scenario(prefix)
    registration = MergeSnapshotScenario.register(prefix:)
    verification = MergeSnapshotScenario.verify(registration, prefix:)
    authorization = MergeSnapshotScenario.authorize(registration, verification, prefix:)
    input = MergeSnapshotScenario.observation_input(registration, authorization, prefix:)
    [ registration, authorization, input ]
  end

  def observation_event(merge_snapshot_id)
    observation_events(merge_snapshot_id).sole
  end

  def observation_events(merge_snapshot_id)
    event_store.read(streams.merge_snapshot(merge_snapshot_id), Coordinator::Write::EventQueries::MERGE_OBSERVATION)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def load(event)
    registry.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
