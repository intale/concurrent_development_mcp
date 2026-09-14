# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteReleaseLeaseSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "withdraws every active intention without recording a released-set snapshot" do
    reservation = setup_reservation
    input = release_input(reservation, command_id: "cmd-withdraw-intentions")

    first = operation.call(input)
    replay = operation.call(input)

    expect(first).to be_success
    expect(replay).to be_success
    expect(replay.value!.emitted_events).to be_empty
    expect(first.value!.data.intentions.map(&:resource_id)).to eq(reservation.resource_ids)
    reservation.receipt.intentions.each do |reference|
      events = read_intention(reference.intention_id)
      expect(events.map(&:type)).to eq(
        [ "ResourceWorkIntentionDeclared", "ResourceWorkIntentionWithdrawn" ]
      )
      withdrawal = events.last
      expect(withdrawal.data.keys).to contain_exactly(
        "intention_id", "resource_id", "fencing_token", "reason"
      )
    end
    expect(first.value!.emitted_events.map(&:type)).not_to include("WriteSetReleased")
  end

  it "allows an exclusive successor after withdrawal and advances the resource fence" do
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ], [ "W-LSE-B", "A-LSE-B", "agent-b" ] ]
    )
    reservation = ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/shared.rb" ])
    operation.call(release_input(reservation, command_id: "cmd-withdraw-owner")).value!

    successor = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "cmd-successor-intention",
      actor: { kind: "agent", id: "agent-b" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-B",
      attempt_id: "A-LSE-B",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [
        {
          resource_id: reservation.resource_ids.sole,
          mode: "exclusive",
          purpose: "Replace the shared implementation"
        }
      ],
      ttl_seconds: 900
    )

    expect(successor).to be_success
    expect(successor.value!.data.intentions.sole.fencing_token).to eq(2)
  end

  it "rejects incomplete membership without withdrawing any intention" do
    reservation = setup_reservation
    input = release_input(reservation, command_id: "cmd-withdraw-incomplete")

    result = operation.call(input.merge(intentions: input.fetch(:intentions).first(1)))

    expect(result.failure).to have_attributes(code: :work_intention_set_snapshot_mismatch)
    reservation.receipt.intentions.each do |reference|
      expect(read_intention(reference.intention_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
  end

  it "withdraws an expanded set when canonical resource order differs from membership order" do
    RepositoryScenario.register(event_store:)
    earlier_resource_id = resolve("Gemfile")
    reservation = setup_reservation
    expansion = Coordinator::Write::Operations::ExecuteExpandWriteSet.new(event_store:).call(
      command_id: "cmd-expand-before-withdrawal",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: reservation.receipt.intention_set_id,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ { resource_id: earlier_resource_id } ]
    ).value!.data
    references = [ *reservation.receipt.intentions, *expansion.added_intentions ]
    input = release_input(reservation, command_id: "cmd-withdraw-expanded").merge(
      intentions: references.map do |reference|
        {
          resource_id: reference.resource_id,
          intention_id: reference.intention_id,
          fencing_token: reference.fencing_token
        }
      end
    )

    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!.data.intentions.map(&:resource_id)).to contain_exactly(
      *references.map(&:resource_id)
    )
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(event_store:, paths: [ "app/a.rb", "app/b.rb" ])
  end

  def release_input(reservation, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: reservation.receipt.intention_set_id,
      intentions: ResourceLeaseOperationScenario.work_intention_inputs(reservation.receipt)
    }
  end

  def read_intention(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    ).reverse
  end

  def resolve(path)
    ResourceScenario.resolve(
      event_store:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path:
    )
  end
end
