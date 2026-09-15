# frozen_string_literal: true

RSpec.describe "history migration target dispatch", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target)) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_payload) do
    Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id: SecureRandom.uuid_v7,
      scope: "project:legacy",
      repository_key: "legacy-app",
      display_name: "Legacy app",
      paths: [ "/workspace/legacy" ],
      remotes: [],
      registered_at: "2026-01-01T12:00:00.000000Z"
    )
  end
  let(:source_event) do
    source_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Repository",
        stream_id: "repository:v1:#{'c' * 64}"
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "RepositoryRegistered",
          data: source_payload.to_h,
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end
  let(:transformer) do
    Coordinator::Write::HistoryMigrations::RepositoryRegisteredV1Transformer.new(
      stream_identity_allocator:
        Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store: source_store)
    )
  end
  let(:planner) do
    Coordinator::Write::HistoryMigrations::FactPlanner.new(
      correlation_allocator:
        Coordinator::Write::HistoryMigrations::CorrelationAllocator.new(event_store: source_store),
      process_step_planner: process_step_planner,
      target_event_planner:
    )
  end
  let(:process_step_planner) { Coordinator::Processes::ProcessStepPlanner.new(event_store: source_store) }
  let(:target_event_planner) do
    Coordinator::Write::HistoryMigrations::TargetEventPlanner.new(event_store: source_store)
  end
  let(:target_plan_builder) do
    Coordinator::Write::HistoryMigrations::TargetPlanBuilder.new(
      process_step_planner:,
      target_event_planner:
    )
  end
  let(:writer) { Coordinator::Write::HistoryMigrations::TargetWriter.new(event_store: target_store) }

  it "plans IDs before dispatch and idempotently persists cohesive facts with source provenance" do
    transformed = transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: source_event.global_position,
      source_event:,
      source_payload:
    ).value!
    target_plan_builder.call(
      migration_id:,
      source_event:,
      transformed_facts: transformed
    ).value!
    first_plan = planner.call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      transformed_facts: transformed
    ).value!
    replay_plan = planner.call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      transformed_facts: transformed
    ).value!

    expect(replay_plan.map { _1.event.id }).to eq(first_plan.map { _1.event.id })
    expect(first_plan.map { _1.event.correlation_id }.uniq).to contain_exactly(
      first_plan.first.event.correlation_id
    )
    expect(first_plan.map { _1.event.caused_by.id }).to eq(first_plan.map { _1.process_step.event.id })

    first_write = writer.call(planned_facts: first_plan)
    replay_write = writer.call(planned_facts: replay_plan)

    expect(first_write).to be_success
    expect(first_write.value!.outcome).to eq("written")
    expect(replay_write.value!.outcome).to eq("existing")
    expect(replay_write.value!.events.map(&:id)).to eq(first_write.value!.events.map(&:id))
    expect(first_write.value!.events.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(first_write.value!.events.map(&:causation_id)).to eq(first_plan.map { _1.process_step.event.id })

    metadata = first_write.value!.events.first.metadata
    expect(metadata).not_to have_key("correlation_id")
    expect(metadata.fetch("migration_source")).to include(
      "event_id" => source_event.id,
      "created_at" => source_event.created_at.utc.iso8601(6)
    )
    expect(first_write.value!.events.flat_map { _1.data.keys }).not_to include("registered_at")
    expect(
      source_store.read(
        first_plan.first.target_stream,
        Coordinator::Write::EventReadCriteria.new(
          event_types: [ "RepositoryRegistered" ],
          maximum_count: 1,
          direction: :asc
        )
      )
    ).to be_empty
  end
end
