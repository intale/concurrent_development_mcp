# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordProcessStepDispatchFailure, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schema_registry) { Coordinator::Write::EventSchemaRegistry.new }
  let(:source_event) do
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "ProcessProbe",
        stream_name: "Source",
        stream_id: id_generator.uuid_v7
      ),
      [
        PgEventstore::Event.new(
          id: id_generator.uuid_v7,
          type: "ProcessSourceProbe",
          data: { "subject_id" => "subject-1" },
          metadata: { "schema_version" => 1 },
          markers: [],
          correlation_id: id_generator.uuid_v7
        )
      ]
    ).sole
  end
  let(:process_step) do
    Coordinator::Write::ProcessSteps::Planner.new(event_store:).call(
      source_event:,
      process_name: "failure-probe",
      step_name: "dispatch-target",
      subject_kind: "probe",
      subject_id: "subject-1",
      rule_version: "failure-probe/v1",
      allocate_target_entity: false
    ).value!
  end

  it "Given a planned step, when its target dispatch fails, then it records one lean terminal fact" do
    persisted = operation.call_command(command, caused_by: process_step.event).value!
    payload = schema_registry.load(
      type: persisted.type,
      schema_version: persisted.metadata.fetch("schema_version"),
      data: persisted.data
    )

    expect(payload).to eq(
      Coordinator::Write::Events::ProcessStepDispatchFailedV1.new(
        process_step_id: process_step.process_step_id,
        target_command_id: process_step.target_command_id,
        code: "concurrency_conflict",
        reason: "Target changed concurrently",
        retryable: true
      )
    )
    expect(persisted).to have_attributes(
      stream_revision: 1,
      causation_id: process_step.event.id,
      correlation_id: source_event.correlation_id
    )
    expect(persisted.metadata).to include(
      "diagnostic_source" => "process-manager-operation",
      "policy_version" => "process-step-dispatch/v1"
    )
  end

  it "replays an identical failure without appending another fact" do
    operation.call_command(command, caused_by: process_step.event).value!

    expect(operation.call_command(command, caused_by: process_step.event).value!).to be_nil
    expect(event_store.read(stream, history).length).to eq(2)
  end

  it "rejects a contradictory terminal failure" do
    operation.call_command(command, caused_by: process_step.event).value!
    result = operation.call_command(
      command(code: "unexpected_failure", reason: "Different failure"),
      caused_by: process_step.event
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:process_step_dispatch_already_failed)
  end

  def command(code: "concurrency_conflict", reason: "Target changed concurrently")
    Coordinator::Write::Commands::RecordProcessStepDispatchFailure.new(
      command_id: id_generator.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "failure-probe"),
      process_step_id: process_step.process_step_id,
      target_command_id: process_step.target_command_id,
      code:,
      reason:,
      retryable: true
    )
  end

  def stream
    streams.process_step(process_step.process_step_id)
  end

  def history
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "ProcessStepPlanned", "ProcessStepDispatchFailed" ],
      maximum_count: 2,
      direction: :asc
    )
  end
end
