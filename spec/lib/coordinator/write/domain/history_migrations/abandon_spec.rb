# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::Abandon do
  subject(:decider) { described_class.new }

  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:checkpoint_event) { PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationStarted") }
  let(:command) do
    Coordinator::Write::Commands::AbandonHistoryMigration.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-operator"),
      migration_id:,
      reason: "Accidental duplicate migration"
    )
  end

  it "records one cohesive abandonment fact for an active migration" do
    decision = decider.call(snapshot: snapshot, command:).value!

    expect(decision.outcome).to eq("abandoned")
    expect(decision.plan.events.map(&:to_h)).to eq(
      [ { migration_id:, reason: "Accidental duplicate migration" } ]
    )
  end

  it "is an event-free semantic retry after abandonment" do
    decision = decider.call(snapshot: snapshot(abandoned: true), command:).value!

    expect(decision.outcome).to eq("existing")
    expect(decision.plan).to be_nil
  end

  it "rejects abandonment after completion" do
    failure = decider.call(snapshot: snapshot(completed: true), command:).failure

    expect(failure.code).to eq(:history_migration_completed)
  end

  def snapshot(completed: false, abandoned: false)
    Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 9,
      page_size: 10,
      next_from_position: 0,
      plan_completed: false,
      application_dependency_wave: 0,
      application_next_from_position: 0,
      completed:,
      abandoned:,
      checkpoint_event:,
      latest_revision: 5
    )
  end
end
