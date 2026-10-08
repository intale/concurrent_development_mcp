# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteExpandWriteSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "preserves existing membership when a new resource exceeds its real boundary budget" do
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ], [ "W-LSE-B", "A-LSE-B", "agent-b" ] ]
    )
    reservation = ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "capacity/owned.rb" ])
    other = ResourceLeaseOperationScenario.reserve(
      event_store:, paths: [ "capacity/addition.rb" ], command_id: "seed-capacity-b",
      agent_id: "agent-b", work_item_id: "W-LSE-B", attempt_id: "A-LSE-B"
    )
    declaration = read_intention(other.receipt.intentions.sole.intention_id).sole
    WorkIntentionHistoryFixture.exhaust_boundary(event_store:, declaration:)

    result = operation.call(
      expand_input(
        reservation, command_id: "cmd-expand-capacity", resources: [ { resource_id: other.resource_ids.sole } ]
      )
    )

    expect(result.failure).to have_attributes(code: :resource_boundary_maintenance_required)
    expect(read_set(reservation.receipt.intention_set_id).map(&:type)).to eq(
      [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet" ]
    )
    mapped = Coordinator::Write::Tasks::ToolResultMapper.new.call(
      result, command_id: "cmd-expand-capacity", tool_name: "work_intention_set_expand"
    )
    expect(mapped).to have_attributes(is_error: true)
    expect(mapped.structured_content.status).to eq("limit_reached")
  end

  it "atomically declares and links each new intention without an expansion snapshot" do
    reservation = setup_reservation
    resource_id = resolve("app/models/b.rb")

    result = operation.call(
      expand_input(
        reservation,
        command_id: "cmd-expand-intentions",
        resources: [ { resource_id:, purpose: "Add the model" } ]
      )
    )

    expect(result).to be_success
    receipt = result.value!.data
    reference = receipt.added_intentions.sole
    expect(reference.resource_id).to eq(resource_id)
    expect(receipt.expires_at).to eq(reservation.receipt.expires_at)
    expect(receipt.intention_count).to eq(2)
    expect(read_intention(reference.intention_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    expect(read_set(receipt.intention_set_id).map(&:type)).to eq(
      [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet", "WorkIntentionAddedToSet" ]
    )
    expect(result.value!.emitted_events.map(&:type)).not_to include("WriteSetExpanded")
  end

  it "rejects already-linked resources as the same idempotent no-change decision" do
    reservation = setup_reservation
    input = expand_input(
      reservation,
      command_id: "cmd-expand-existing",
      resources: reservation.resource_ids.map { { resource_id: _1 } }
    )

    first = operation.call(input)
    second = operation.call(input)

    expect(first.failure).to have_attributes(code: :work_intention_set_unchanged)
    expect(second.failure).to have_attributes(code: :work_intention_set_unchanged)
    expect(read_set(reservation.receipt.intention_set_id).length).to eq(2)
  end

  it "rejects the entire expansion when a new shared intention overlaps active exclusive work" do
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ], [ "W-LSE-B", "A-LSE-B", "agent-b" ] ]
    )
    owner = ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [ "app/a.rb" ],
      command_id: "seed-shared-a"
    )
    exclusive = ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [
        {
          path: "app/busy.rb",
          kind: "file",
          mode: "exclusive",
          purpose: "Replace the implementation",
          context: "Other edits would be discarded"
        }
      ],
      command_id: "seed-exclusive-b",
      agent_id: "agent-b",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B"
    )
    free = resolve("app/free.rb")

    result = operation.call(
      expand_input(
        owner,
        command_id: "cmd-expand-conflict",
        resources: [ { resource_id: free }, { resource_id: exclusive.resource_ids.sole } ]
      )
    )

    expect(result.failure).to have_attributes(code: :work_intention_conflict)
    expect(result.failure.details.fetch(:blockers).sole).to include(
      resource_id: exclusive.resource_ids.sole,
      mode: "exclusive",
      purpose: "Replace the implementation",
      context: "Other edits would be discarded"
    )
    expect(read_set(owner.receipt.intention_set_id).length).to eq(2)
  end

  it "rejects an inactive Resource before changing set membership" do
    reservation = setup_reservation
    inactive = resolve("app/removed.rb")
    Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:).call(
      command_id: "cmd-remove-expanded-resource",
      actor: { kind: "agent", id: "agent-a" },
      resource_id: inactive,
      reason: "removed"
    ).value!

    result = operation.call(
      expand_input(
        reservation,
        command_id: "cmd-expand-inactive",
        resources: [ { resource_id: inactive } ]
      )
    )

    expect(result.failure).to have_attributes(code: :resource_not_active)
    expect(read_set(reservation.receipt.intention_set_id).length).to eq(2)
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/models/a.rb" ])
  end

  def expand_input(reservation, command_id:, resources:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: reservation.receipt.intention_set_id,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources:
    }
  end

  def resolve(path)
    ResourceScenario.resolve(
      event_store:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path:
    )
  end

  def read_set(set_id)
    event_store.read(
      streams.work_intention_set(set_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
    )
  end

  def read_intention(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    ).reverse
  end
end
