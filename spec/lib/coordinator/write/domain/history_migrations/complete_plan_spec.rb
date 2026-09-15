# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::CompletePlan do
  subject(:decider) { described_class.new }

  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:checkpoint_event) { PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationStarted") }
  let(:command) do
    Coordinator::Write::Commands::CompleteHistoryMigrationPlan.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      migration_id:
    )
  end

  it "closes the plan directly when the frozen source range is empty" do
    decision = decider.call(snapshot: snapshot(source_upper_position: nil), command:).value!

    expect(decision.outcome).to eq("plan_completed")
    expect(decision.plan.events.map(&:to_h)).to eq([ { migration_id: } ])
  end

  it "requires nonempty migrations to be closed by their final planned page" do
    failure = decider.call(snapshot: snapshot(source_upper_position: 3), command:).failure

    expect(failure.code).to eq(:history_migration_page_required)
  end

  def snapshot(source_upper_position:)
    Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position:,
      page_size: 10,
      next_from_position: 0,
      plan_completed: false,
      application_next_from_position: 0,
      completed: false,
      checkpoint_event:,
      latest_revision: 5
    )
  end
end
