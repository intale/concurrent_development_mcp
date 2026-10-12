# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRenewWorkIntentionSet, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "plans stable child identities and a deadline without renewing any member yet" do
    reservation = setup_reservation

    command = stored_command(renew_input(reservation, command_id: "cmd-renew-intentions"))
    result = operation.call_command(command)

    expect(result).to be_success
    planned = Coordinator::Write::WorkIntentionRenewals::Loader.new(event_store:).call(command.command_id)
    expect(planned.state.assignments.map(&:intention_id)).to eq(command.intentions.map(&:intention_id))
    expect(planned.state.assignments.map(&:fencing_token)).to eq([ 1, 1 ])
    expect(planned.state.assignments.flat_map { [ _1.renew_command_id, _1.outcome_command_id ] }.uniq.length).to eq(4)
    planned.state.assignments.each do |reference|
      events = read_intention(reference.intention_id)
      expect(events.map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
    replay = operation.call_command(command).value!
    expect(replay.id).to eq(result.value!.id)
    expect(Coordinator::Write::WorkIntentionRenewals::Loader.new(event_store:).call(command.command_id).events.map(&:id)).to eq(planned.events.map(&:id))
  end

  it "rejects incomplete and stale member observations without partial renewal" do
    reservation = setup_reservation
    intentions = WorkIntentionOperationScenario.work_intention_inputs(reservation.receipt)

    incomplete = operation.call_command(stored_command(
      renew_input(reservation, command_id: "cmd-renew-incomplete").merge(intentions: intentions.first(1))
    ))
    stale = operation.call_command(stored_command(
      renew_input(reservation, command_id: "cmd-renew-stale").merge(
        intentions: intentions.map.with_index { |entry, index| index.zero? ? entry.merge(fencing_token: 2) : entry }
      )
    ))

    expect(incomplete.failure).to have_attributes(code: :work_intention_set_snapshot_mismatch)
    expect(stale.failure).to have_attributes(code: :work_intention_reference_mismatch)
    reservation.receipt.intentions.each do |reference|
      expect(read_intention(reference.intention_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
  end

  it "still plans the Saga when every member can satisfy the shorter request without a new effect" do
    reservation = setup_reservation
    result = operation.call_command(stored_command(renew_input(reservation, command_id: "cmd-renew-shorter").merge(ttl_seconds: 30)))
    expect(result).to be_success
    expect(result.value!.type).to eq("WorkIntentionSetRenewalRequested")
    reservation.receipt.intentions.each do |reference|
      expect(read_intention(reference.intention_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    end
  end

  it "renews an expanded set when canonical resource order differs from membership order" do
    RepositoryScenario.register(event_store:)
    earlier_resource_id = resolve("Gemfile")
    reservation = setup_reservation
    expansion = Coordinator::Write::Operations::ExecuteExpandWorkIntentionSet.new(event_store:).call(
      command_id: "cmd-expand-before-renewal",
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
    input = renew_input(reservation, command_id: "cmd-renew-expanded").merge(
      intentions: references.map do |reference|
        {
          resource_id: reference.resource_id,
          intention_id: reference.intention_id,
          fencing_token: reference.fencing_token
        }
      end
    )

    result = operation.call_command(stored_command(input))

    expect(result).to be_success
    planned = Coordinator::Write::WorkIntentionRenewals::Loader.new(event_store:).call(result.value!.stream.stream_id)
    expect(planned.state.assignments.map(&:resource_id)).to contain_exactly(
      *references.map(&:resource_id)
    )
  end

  def setup_reservation
    WorkIntentionOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    WorkIntentionOperationScenario.declare(event_store:, paths: [ "app/a.rb", "app/b.rb" ])
  end

  def stored_command(input)
    prepared = Coordinator::Write::Operations::PrepareRenewWorkIntentionSet.new.call(input).value!
    prepared.class.new(prepared.attributes.merge(command_id: SecureRandom.uuid_v7))
  end

  def renew_input(reservation, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: reservation.receipt.intention_set_id,
      intentions: WorkIntentionOperationScenario.work_intention_inputs(reservation.receipt),
      ttl_seconds: 900
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
