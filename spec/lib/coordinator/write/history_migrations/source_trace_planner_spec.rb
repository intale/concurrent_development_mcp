# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceTracePlanner, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:planner) { described_class.new(event_store:) }
  let(:target_event_planner) do
    Coordinator::Write::HistoryMigrations::TargetEventPlanner.new(event_store:)
  end

  it "resolves immediate target causation and carries an endpoint through omitted source facts" do
    root = append_source(type: "LegacyRoot")
    root_plans = [
      target_plan(root, step: "root-first", type: "RepositoryRegistered"),
      target_plan(root, step: "root-second", type: "RepositoryPathAdded")
    ]

    root_trace = planner.call(migration_id:, source_event: root, target_plans: root_plans)
    replay = planner.call(migration_id:, source_event: root, target_plans: root_plans)
    omitted = append_source(type: "LegacyOmitted", caused_by: root)
    omitted_trace = planner.call(migration_id:, source_event: omitted, target_plans: [])
    child = append_source(type: "LegacyChild", caused_by: omitted)

    expect(root_trace).to be_success
    expect(root_trace.value!.target_endpoint).to eq(root_plans.last.target_event)
    expect(root_trace.value!.outcome).to eq("created")
    expect(replay.value!).to have_attributes(
      target_endpoint: root_plans.last.target_event,
      outcome: "existing"
    )
    expect(omitted_trace.value!.target_endpoint).to eq(root_plans.last.target_event)
    expect(planner.causal_parent(migration_id:, source_event: child).value!).to eq(
      root_plans.last.target_event
    )
  end

  it "records a nil endpoint for a causationless source event with no target facts" do
    source = append_source(type: "LegacyIgnored")

    result = planner.call(migration_id:, source_event: source, target_plans: [])

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      source_event_id: source.id,
      source_causation_id: nil,
      target_endpoint: nil
    )
  end

  it "rejects a source event whose causal parent has not been planned" do
    missing_parent = PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "MissingParent",
      correlation_id: SecureRandom.uuid_v7
    )
    source = append_source(type: "LegacyChild", caused_by: missing_parent)

    result = planner.call(migration_id:, source_event: source, target_plans: [])

    expect(result).to be_failure
    expect(result.failure).to include(
      code: :ambiguous_source_reference,
      source_event_id: source.id
    )
  end

  private

  def append_source(type:, caused_by: nil)
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "Legacy",
        stream_name: "TraceSource",
        stream_id: SecureRandom.uuid_v7
      ),
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type:, caused_by:) ]
    ).sole
  end

  def target_plan(source_event, step:, type:)
    target_event_planner.call(
      migration_id:,
      source_event:,
      transformation_step: step,
      target_stream: Coordinator::Write::StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "Repository",
        stream_id: SecureRandom.uuid_v7
      ),
      target_event_id: SecureRandom.uuid_v7,
      target_event_type: type,
      caused_by: source_event
    ).value!
  end
end
