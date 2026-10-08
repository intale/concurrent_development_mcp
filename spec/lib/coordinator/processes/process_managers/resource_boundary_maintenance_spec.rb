# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::ResourceBoundaryMaintenance, :event_store do
  subject(:process_manager) do
    described_class.new(
      event_store:,
      operation: Coordinator::Write::Operations::ExecuteRollResourceBoundaryEpoch.new(
        event_store:,
        rollover_policy: Coordinator::Write::WorkIntentionBoundaryRolloverPolicy.new(minimum_delta_event_count: 1)
      )
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:intention_id) { SecureRandom.uuid_v7 }
  let(:marker) do
    Coordinator::Shared::ResourceMarkerCodec.new.boundary(
      repository_id:, role: "resource-exact", normalized_path: "docs/guide.md"
    )
  end

  it "does not plan an impossible empty-boundary rollover for an active declaration" do
    source = append_declaration

    expect(process_manager.call(source)).to be_nil
    expect(steps_for(source)).to be_empty
    expect(epoch_event).to be_nil
  end

  it "uses the source cutoff even if the latest intention state is already withdrawn" do
    declaration = append_declaration
    source = append(
      Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
        intention_id:, resource_id:, fencing_token: 1, expires_at: "2099-01-02T00:00:00.000000Z"
      ), caused_by: declaration
    )
    append_withdrawal(source)

    expect(process_manager.call(source)).to be_nil
    expect(steps_for(source)).to be_empty
    expect(epoch_event).to be_nil
  end

  it "avoids planning and scanning the boundary even when active renewal history exceeds the decision budget" do
    declaration = append_declaration
    source = WorkIntentionHistoryFixture.exhaust_boundary(event_store:, declaration:).last

    expect(process_manager.call(source)).to be_nil
    expect(steps_for(source)).to be_empty
    expect(epoch_event).to be_nil
  end

  it "still evaluates an already elapsed declaration at the native cutoff" do
    source = append_declaration(expires_at: "2000-01-01T00:00:00.000000Z")

    expect(process_manager.call(source)).to be_nil
    expect(steps_for(source).length).to eq(1)
    expect(epoch_event.data).to include("epoch" => 1, "through_global_position" => source.global_position)
  end

  it "rolls a withdrawn boundary idempotently with native immediate-parent tracing" do
    source = append_withdrawal(append_declaration)

    expect(process_manager.call(source)).to be_nil
    first = epoch_event
    expect(process_manager.call(source)).to be_nil
    step = steps_for(source).sole
    expect(epoch_event.id).to eq(first.id)
    expect(first.data).to include("epoch" => 1, "through_global_position" => source.global_position)
    expect(first.causation_id).to eq(step.id)
    expect(step.causation_id).to eq(source.id)
    expect([ first, step ].map(&:correlation_id)).to eq([ source.correlation_id ] * 2)
  end

  it "does not hide an active renewal without an authoritative declaration" do
    source = append(
      Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
        intention_id:, resource_id:, fencing_token: 1, expires_at: "2099-01-01T00:00:00.000000Z"
      )
    )

    expect { process_manager.call(source) }.to raise_error(described_class::Rejected, /missing its declaration/)
    expect(steps_for(source)).to be_empty
  end

  private

  def append_declaration(expires_at: "2099-01-01T00:00:00.000000Z")
    append(
      Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
        intention_id:, set_id: SecureRandom.uuid_v7, resource_id:, repository_id:,
        change_set_id: "CS-boundary", work_item_id: "WI-boundary", attempt_id: "ATT-boundary",
        agent_id: "boundary-agent", mode: "shared", purpose: "edit", context: nil,
        object_format: "sha1", base_commit_oid: "a" * 40, base_blob_oid: nil,
        fencing_token: 1, expires_at:
      )
    )
  end

  def append_withdrawal(source)
    append(
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(
        intention_id:, resource_id:, fencing_token: 1, reason: "work_finished"
      ), caused_by: source
    )
  end

  def append(payload, caused_by: nil)
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload, event_id: SecureRandom.uuid_v7,
      metadata: Coordinator::Write::EventMetadata.new(
        command_id: SecureRandom.uuid_v7, actor_kind: "agent", actor_id: "boundary-agent",
        recorded_by: "coordinator", policy_version: "work-intention/v1"
      ), markers: [ marker ], caused_by:
    )
    event_store.append(streams.resource_work_intention(intention_id), [ event ]).sole
  end

  def steps_for(source)
    step_marker = Coordinator::Shared::Markers::CodecV2.new.call(
      purpose: "process-step", components: [
        { dimension: "process-name", value: "resource-boundary-maintenance" },
        { dimension: "source-event-id", value: source.id },
        { dimension: "step-name", value: "roll-resource-boundary-epoch" },
        { dimension: "subject-kind", value: "boundary-index" },
        { dimension: "subject-id", value: "0" }
      ]
    ).value!.marker
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorControl", stream_name: "ProcessStep",
        event_types: [ "ProcessStepPlanned" ], markers: [ step_marker ], maximum_count: 1, direction: :asc
      )
    )
  end

  def epoch_event
    event_store.read_latest_marked(
      streams.resource_boundary_epoch(repository_id),
      Coordinator::Write::LatestMarkedEventReadCriteria.new(
        event_type: "ResourceBoundaryEpochRolled", marker:
      )
    ).first
  end
end
