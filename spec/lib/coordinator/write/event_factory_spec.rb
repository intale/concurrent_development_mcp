# frozen_string_literal: true

RSpec.describe Coordinator::Write::EventFactory do
  subject(:factory) { described_class.new }

  let(:domain_event) do
    Coordinator::Write::Events::ChangeSetCreatedV1.new(
      change_set_id: "CS-100",
      goal: "Coordinate an API change",
      created_at: "2026-08-20T14:10:00.000000Z"
    )
  end
  let(:metadata) do
    Coordinator::Write::EventMetadata.new(
      command_id: "cmd-100",
      actor_kind: "agent",
      actor_id: "planner-1",
      recorded_by: "coordinator",
      correlation_id: "cmd-100",
      policy_version: nil
    )
  end
  let(:event_id) { "018fd0f0-0000-7000-8000-000000000001" }

  it "serializes one already-decided typed event with stable metadata and markers" do
    event = factory.build!(
      event: domain_event,
      event_id:,
      metadata:,
      markers: [ "change-set:CS-100", "command:cmd-100", "change-set:CS-100" ]
    )

    expect(event).to be_a(PgEventstore::Event)
    expect(event.id).to eq(event_id)
    expect(event.type).to eq("ChangeSetCreated")
    expect(event.data).to eq(
      "change_set_id" => "CS-100",
      "goal" => "Coordinate an API change",
      "created_at" => "2026-08-20T14:10:00.000000Z"
    )
    expect(event.metadata).to eq(
      "command_id" => "cmd-100",
      "actor_kind" => "agent",
      "actor_id" => "planner-1",
      "recorded_by" => "coordinator",
      "correlation_id" => "cmd-100",
      "schema_version" => 1
    )
    expect(event.markers).to eq([ "change-set:CS-100", "command:cmd-100" ])
    expect(event.markers).not_to be_frozen
  end

  it "builds a fresh pg_eventstore event for each transaction attempt" do
    attributes = {
      event: domain_event,
      event_id:,
      metadata:,
      markers: [ "command:cmd-100" ]
    }

    first = factory.build!(**attributes)
    second = factory.build!(**attributes)

    expect(first).not_to equal(second)
    expect(first).to eq(second)
  end

  it "preserves explicit source-event causation" do
    source = PgEventstore::Event.new(type: "ChangeSetActivated")

    event = factory.build!(
      event: domain_event,
      event_id:,
      metadata:,
      markers: [],
      caused_by: source
    )

    expect(event.caused_by).to equal(source)
  end

  it "rejects an invalid event ID value" do
    expect do
      factory.build!(event: domain_event, event_id: "not-a-uuid", metadata:, markers: [])
    end.to raise_error(Dry::Types::ConstraintError)
  end

  it "loads historical string-key payloads through the versioned registry" do
    loaded = Coordinator::Write::EventSchemaRegistry.new.load(
      type: "ChangeSetCreated",
      schema_version: 1,
      data: {
        "change_set_id" => "CS-100",
        "goal" => "Coordinate an API change",
        "created_at" => "2026-08-20T14:10:00.000000Z"
      }
    )

    expect(loaded).to eq(domain_event)
  end

  it "rejects unknown fields when loading a historical payload" do
    expect do
      Coordinator::Write::EventSchemaRegistry.new.load(
        type: "ChangeSetCreated",
        schema_version: 1,
        data: domain_event.to_h.merge("unknown" => true)
      )
    end.to raise_error(Dry::Struct::Error, /unexpected keys/)
  end

  it "reconstructs nested dry values from historical event hashes" do
    loaded = Coordinator::Write::EventSchemaRegistry.new.load(
      type: "WorkItemDependencyDeclared",
      schema_version: 1,
      data: {
        "change_set_id" => "CS-100",
        "dependency_id" => "DEP-1",
        "producer_work_item_id" => "W-100",
        "consumer_work_item_id" => "W-200",
        "dependency_kind" => "requires_artifact",
        "required_output" => { "kind" => "artifact", "key" => "openapi-v1" },
        "declared_at" => "2026-08-20T14:14:00.000000Z"
      }
    )

    expect(loaded.required_output).to eq(
      Coordinator::Write::RequiredOutput.new(kind: "artifact", key: "openapi-v1")
    )
  end
end
