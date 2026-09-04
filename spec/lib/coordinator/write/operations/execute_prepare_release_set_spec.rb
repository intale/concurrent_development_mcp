# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecutePrepareReleaseSet, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:registry) { Coordinator::Write::EventSchemaRegistry.new }

  it "prepares one immutable ordered set and leaves replay ownership to the registered Command lifecycle" do
    input = ReleaseSetScenario.prepare_input(prefix: "success")

    first = operation.call(input).value!
    replay = operation.call(input)
    physical = preparation_events(input.fetch(:release_set_id))
    payloads = physical.map { load(_1) }
    created, *members, prepared = physical
    prepared_payload = payloads.last

    expect(replay.failure.code).to eq(:release_set_id_already_used)
    expect(physical.map(&:type)).to eq([
      "ReleaseSetCreated",
      "ReleaseSetMemberAdded",
      "ReleaseSetMemberAdded",
      "ReleaseSetPrepared"
    ])
    expect(payloads.first).to have_attributes(
      release_set_id: input.fetch(:release_set_id),
      change_set_id: "CS-release-success"
    )
    repository_ids = ReleaseSetScenario::REPOSITORIES.map { RepositoryScenario.repository_id(_1) }
    expect(payloads[1, 2].map(&:member_position)).to eq([ 1, 2 ])
    expect(payloads[1, 2].map(&:repository_id)).to eq(repository_ids)
    expect(payloads[1, 2].map(&:candidate_id)).to all(match(/\ACAN-/))
    expect(prepared_payload.to_h).to eq(release_set_id: input.fetch(:release_set_id))
    expect(prepared.metadata.fetch("release_digest")).to match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    expect(physical).to all(satisfy { |event| event.markers.include?("release-set:REL-success") })
    expect(created.markers).to include(
      "release-set:REL-success",
      "change-set:CS-release-success",
      *repository_ids.map { "repository:#{_1}" }
    )
    expect(physical.drop(1).map(&:causation_id)).to eq(physical.each_cons(2).map { _1.first.id })
    expect(physical.map(&:correlation_id).uniq).to contain_exactly(created.correlation_id)
    expect(prepared.metadata).not_to have_key("prepared_at")
    expect(first.data.prepared_event).to eq(reference(prepared))
    expect(command_events(input.fetch(:command_id))).to be_empty
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
    expect(preparation_events(input.fetch(:release_set_id)).length).to eq(4)
  end

  def preparation_events(release_set_id)
    event_store.read(streams.release_set(release_set_id), Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION)
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

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end
end
