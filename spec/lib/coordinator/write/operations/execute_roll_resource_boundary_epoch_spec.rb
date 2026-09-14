# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRollResourceBoundaryEpoch, :event_store do
  subject(:operation) do
    described_class.new(
      event_store:,
      rollover_policy: Coordinator::Write::WorkIntentionBoundaryRolloverPolicy.new(
        minimum_delta_event_count: 2
      )
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:event_factory) { Coordinator::Write::EventFactory.new }
  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { id_generator.uuid_v7 }
  let(:intention_id) { id_generator.uuid_v7 }
  let(:set_id) { id_generator.uuid_v7 }
  let(:resource_id) { id_generator.uuid_v7 }
  let(:boundary_markers) do
    [ "docs/guide.md", "docs" ].map do |path|
      Coordinator::Shared::ResourceMarkerCodec.new.boundary(
        repository_id:,
        role: "resource-exact",
        normalized_path: path
      )
    end
  end
  let(:source_event) { append_intention_history }

  it "checkpoints a proven-empty historical boundary without snapshotting aggregate state" do
    first_step = process_step(source_event, subject_id: "first")
    first = operation.call_command(
      command(first_step, marker: boundary_markers.first),
      caused_by: first_step.event
    ).value!
    second_step = process_step(source_event, subject_id: "second")
    second = operation.call_command(
      command(second_step, marker: boundary_markers.second),
      caused_by: second_step.event
    ).value!

    expect([ first.stream_revision, second.stream_revision ]).to eq([ 0, 1 ])
    expect(first.data).to eq(
      "repository_id" => repository_id,
      "boundary_marker" => boundary_markers.first,
      "epoch" => 1,
      "through_global_position" => source_event.global_position
    )
    expect(first.metadata).to include("policy_version" => "resource-boundary-maintenance/v3")
    expect(first.data.keys).not_to include("active_leases", "active_intentions", "rolled_at")

    loaded = Coordinator::Write::WorkIntentionBoundaryLoader.new(event_store:).call(
      [ boundary_markers.first ],
      repository_id:,
      at: source_event.created_at.utc.iso8601(6)
    ).value!
    expect(loaded).to have_attributes(
      delta_event_count: 0,
      active_state_count: 0,
      states: [],
      active_observations: []
    )
    expect(loaded.epochs.sole).to have_attributes(
      epoch: 1,
      through_global_position: source_event.global_position
    )
  end

  it "does not roll while an intention remains active at the immutable cutoff" do
    declaration = append_declaration(boundary_markers)
    step = process_step(declaration, subject_id: "active")

    result = operation.call_command(
      command(step, marker: boundary_markers.first, source_event: declaration),
      caused_by: step.event
    )

    expect(result.value!).to be_nil
  end

  private

  def append_intention_history
    declaration = append_declaration(boundary_markers)
    append(
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(
        intention_id:,
        resource_id:,
        fencing_token: 1,
        reason: "work_finished"
      ),
      markers: boundary_markers,
      caused_by: declaration,
      expected_revision: 0
    )
  end

  def append_declaration(markers)
    append(
      Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
        intention_id:,
        set_id:,
        resource_id:,
        repository_id:,
        change_set_id: "CS-boundary",
        work_item_id: "WI-boundary",
        attempt_id: "ATT-boundary",
        agent_id: "agent-boundary",
        mode: "shared",
        purpose: "edit",
        context: nil,
        object_format: "sha1",
        base_commit_oid: "a" * 40,
        base_blob_oid: "b" * 40,
        fencing_token: 1,
        expires_at: "2099-01-01T00:00:00.000000Z"
      ),
      markers:
    )
  end

  def append(payload, markers:, caused_by: nil, expected_revision: nil)
    physical = event_factory.build!(
      event: payload,
      event_id: id_generator.uuid_v7,
      metadata: Coordinator::Write::EventMetadata.new(
        command_id: id_generator.uuid_v7,
        actor_kind: "agent",
        actor_id: "boundary-spec",
        recorded_by: "coordinator",
        policy_version: "work-intention/v1"
      ),
      markers: [ *markers, "command:#{id_generator.uuid_v7}" ],
      caused_by:
    )
    options = expected_revision.nil? ? {} : { expected_revision: }
    event_store.append(streams.resource_work_intention(intention_id), [ physical ], **options).sole
  end

  def process_step(event, subject_id:)
    Coordinator::Write::ProcessSteps::Planner.new(event_store:).call(
      source_event: event,
      process_name: "resource-boundary-spec",
      step_name: "roll",
      subject_kind: "boundary",
      subject_id:,
      rule_version: "resource-boundary-rollover/v3",
      allocate_target_entity: false
    ).value!
  end

  def command(step, marker:, source_event: self.source_event)
    Coordinator::Write::Commands::RollResourceBoundaryEpoch.new(
      command_id: step.target_command_id,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "resource-boundary-spec"),
      repository_id:,
      boundary_marker: marker,
      source_event_id: source_event.id,
      source_global_position: source_event.global_position,
      source_created_at: source_event.created_at.utc.iso8601(6)
    )
  end
end
