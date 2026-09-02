# frozen_string_literal: true

RSpec.describe Coordinator::Write::ProcessSteps::Planner, :event_store do
  subject(:planner) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:schema_registry) { Coordinator::Write::EventSchemaRegistry.new }

  def source_event
    @source_event ||= begin
      event = PgEventstore::Event.new(
        id: id_generator.uuid_v7,
        type: "ProcessSourceProbe",
        data: { "subject_id" => "subject-1" },
        metadata: { "schema_version" => 1 },
        markers: [],
        correlation_id: id_generator.uuid_v7
      )
      stream = Coordinator::Write::StreamReference.new(
        context: "ProcessProbe",
        stream_name: "Source",
        stream_id: id_generator.uuid_v7
      )
      event_store.append(stream, [ event ]).sole
    end
  end

  def plan
    planner.call(
      source_event:,
      process_name: "identity-probe",
      step_name: "create-child",
      subject_kind: "probe",
      subject_id: "subject-1",
      rule_version: "identity-probe/v1",
      allocate_target_entity: true
    )
  end

  def payload(event)
    schema_registry.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  it "persists a UUIDv7 plan before dispatch and reuses it on source redelivery" do
    first = plan.value!
    replay = plan.value!
    first_payload = payload(first.event)
    replay_payload = payload(replay.event)

    expect(first.outcome).to eq("created")
    expect(replay.outcome).to eq("existing")
    expect(replay.event.id).to eq(first.event.id)
    expect(replay_payload).to eq(first_payload)
    expect(first_payload.process_step_id).to eq(first.identity)
    expect([
      first_payload.process_step_id,
      first_payload.target_command_id,
      first_payload.target_entity_id,
      first.event.id
    ]).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(first.event.stream).to have_attributes(
      context: "CoordinatorControl",
      stream_name: "ProcessStep",
      stream_id: first_payload.process_step_id
    )
  end

  it "preserves native Saga correlation and immediate causation without metadata copies" do
    persisted = plan.value!.event

    expect(persisted.causation_id).to eq(source_event.id)
    expect(persisted.correlation_id).to eq(source_event.correlation_id)
    expect(persisted.metadata).not_to have_key("causation_id")
    expect(persisted.metadata).not_to have_key("correlation_id")
    expect(persisted.metadata).to include(
      "actor_kind" => "system",
      "actor_id" => "identity-probe",
      "actor_authenticated" => false,
      "recorded_by" => "coordinator",
      "rule_version" => "identity-probe/v1",
      "schema_version" => 1
    )
  end

  it "stores one readable selector and no digest-derived identity" do
    persisted = plan.value!.event
    marker = persisted.markers.grep(/\Acompound:process-step:v2\|/).sole
    decoded = Coordinator::Shared::Markers::CodecV2.new.decode(marker).value!

    expect(decoded.definition.components.to_h { [ _1.dimension, _1.value ] }).to eq(
      "process-name" => "identity-probe",
      "source-event-id" => source_event.id,
      "step-name" => "create-child",
      "subject-id" => "subject-1",
      "subject-kind" => "probe"
    )
    expect(marker).not_to match(/sha|md5/i)
    expect(persisted.stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
  end
end
