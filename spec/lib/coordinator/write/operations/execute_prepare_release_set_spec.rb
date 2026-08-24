# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecutePrepareReleaseSet, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:registry) { Coordinator::Write::EventSchemaRegistry.new }

  it "prepares one immutable ordered set from current exact grants and replays its Command" do
    input = ReleaseSetScenario.prepare_input(prefix: "success")

    first = operation.call(input).value!
    replay = operation.call(input).value!
    physical = preparation_events(input.fetch(:release_set_id)).sole
    payload = load(physical)

    expect(first).to eq(replay)
    expect(payload).to have_attributes(
      release_set_id: input.fetch(:release_set_id),
      change_set_id: "CS-release-success",
      policy_version: "release-set-preparation/v1"
    )
    expect(payload.ordered_members.map(&:position)).to eq([ 1, 2 ])
    expect(payload.ordered_members.map(&:repository_id)).to eq(%w[billing ledger])
    expect(payload.release_digest).to match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    expect(physical.markers).to include(
      "release-set:REL-success",
      "change-set:CS-release-success",
      "repository:billing",
      "repository:ledger"
    )
    expect(command_events(input.fetch(:command_id)).length).to eq(1)
  end

  it "rejects a grant after its authoritative policy context changes" do
    input = ReleaseSetScenario.prepare_input(prefix: "stale")
    CandidateObligationScenario.activate_policy(
      prefix: "release-stale",
      change_set_id: "CS-release-stale",
      level: "merge_gate"
    )

    result = operation.call(input)

    expect(result.failure.code).to eq(:release_member_authorization_stale)
    expect(preparation_events(input.fetch(:release_set_id))).to be_empty
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "rejects a new Command when the ReleaseSet ID was already used" do
    input = ReleaseSetScenario.prepare_input(prefix: "used")
    operation.call(input).value!

    result = operation.call(input.merge(command_id: "cmd-release-prepare-used-again"))

    expect(result.failure.code).to eq(:release_set_id_already_used)
    expect(preparation_events(input.fetch(:release_set_id)).length).to eq(1)
  end

  def preparation_events(release_set_id)
    event_store.read(streams.release_set(release_set_id), Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def load(event)
    registry.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
