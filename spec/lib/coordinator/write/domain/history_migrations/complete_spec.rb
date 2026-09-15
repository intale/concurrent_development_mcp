# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::Complete do
  subject(:decider) { described_class.new }

  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:checkpoint_event) do
    PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationApplicationCursorAdvanced")
  end
  let(:command) do
    Coordinator::Write::Commands::CompleteHistoryMigration.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      migration_id:
    )
  end

  it "completes only after every planned source page has been applied" do
    decision = decider.call(snapshot: snapshot(application_next_from_position: 10), command:).value!

    expect(decision.outcome).to eq("completed")
    expect(decision.plan.events.map(&:to_h)).to eq([ { migration_id: } ])
  end

  it "rejects completion while application remains behind the frozen range" do
    failure = decider.call(snapshot: snapshot(application_next_from_position: 0), command:).failure

    expect(failure.code).to eq(:history_migration_application_incomplete)
  end

  def snapshot(application_next_from_position:)
    Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 9,
      page_size: 10,
      next_from_position: 10,
      plan_completed: true,
      application_next_from_position:,
      completed: false,
      checkpoint_event:,
      latest_revision: 8
    )
  end
end
