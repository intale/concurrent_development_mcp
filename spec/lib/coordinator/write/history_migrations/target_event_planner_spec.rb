# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::TargetEventPlanner, :event_store do
  subject(:planner) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:target_stream) do
    Coordinator::Write::StreamReference.new(
      context: "DevelopmentPlanning",
      stream_name: "Repository",
      stream_id: SecureRandom.uuid_v7
    )
  end
  let(:source_stream) do
    Coordinator::Write::StreamReference.new(
      context: "LegacyDevelopmentPlanning",
      stream_name: "Repository",
      stream_id: "repository:legacy"
    )
  end
  let(:source_events) do
    event_store.append(
      source_stream,
      [
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "RepositoryRegistered"),
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "RepositoryRenamed")
      ]
    )
  end

  it "durably assigns ordered target revisions without writing the target stream" do
    first_id = SecureRandom.uuid_v7
    second_id = SecureRandom.uuid_v7
    first = plan(source_events.first, step: "register-repository", event_id: first_id, type: "RepositoryRegistered")
    replay = plan(source_events.first, step: "register-repository", event_id: first_id, type: "RepositoryRegistered")
    second = plan(source_events.last, step: "rename-repository", event_id: second_id, type: "RepositoryDisplayNameChanged")

    expect(first).to be_success
    expect(replay).to be_success
    expect(second).to be_success
    expect(first.value!.outcome).to eq("created")
    expect(replay.value!.outcome).to eq("existing")
    expect(second.value!.outcome).to eq("created")
    expect(first.value!.target_event.stream_revision).to eq(0)
    expect(second.value!.target_event.stream_revision).to eq(1)
    expect(first.value!.target_event.event_id).to eq(first_id)
    expect(second.value!.target_event.event_id).to eq(second_id)
    expect(target_events).to be_empty

    marker = first.value!.marker
    expect(marker).to start_with("compound:history-migration-target-event-plan:v2")
    expect(marker).to include("source-event=")
    expect(marker).not_to match(/sha|md5/i)
  end

  it "rejects a different target for an existing source transformation step" do
    source = source_events.first
    first = plan(
      source,
      step: "register-repository",
      event_id: SecureRandom.uuid_v7,
      type: "RepositoryRegistered"
    )
    mismatch = plan(
      source,
      step: "register-repository",
      event_id: SecureRandom.uuid_v7,
      type: "RepositoryRegistered"
    )

    expect(first).to be_success
    expect(mismatch).to be_failure
    expect(mismatch.failure.code).to eq(:existing_target_plan_mismatch)
  end

  private

  def plan(source_event, step:, event_id:, type:)
    planner.call(
      migration_id:,
      source_event:,
      transformation_step: step,
      target_stream:,
      target_event_id: event_id,
      target_event_type: type,
      caused_by: source_event
    )
  end

  def target_events
    event_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "RepositoryRegistered", "RepositoryDisplayNameChanged" ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end
end
