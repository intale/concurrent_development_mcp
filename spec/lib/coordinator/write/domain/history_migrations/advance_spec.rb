# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::Advance do
  subject(:decider) { described_class.new }

  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:page_id) { SecureRandom.uuid_v7 }
  let(:checkpoint_event) { PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationStarted") }
  let(:snapshot) do
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
      completed: false,
      checkpoint_event:,
      latest_revision: 5
    )
  end
  let(:page) do
    Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(
      [
        Coordinator::Write::Events::HistoryMigrationPageCreatedV1.new(page_id:),
        Coordinator::Write::Events::HistoryMigrationPageAddedToMigrationV1.new(page_id:, migration_id:),
        Coordinator::Write::Events::HistoryMigrationPageSourceRangeSelectedV1.new(
          page_id:,
          from_position: 0,
          to_position: 9
        ),
        Coordinator::Write::Events::HistoryMigrationPageSourceEventCountRecordedV1.new(
          page_id:,
          source_event_count: 10
        ),
        Coordinator::Write::Events::HistoryMigrationPageTargetEventCountRecordedV1.new(
          page_id:,
          target_event_count: 12
        ),
        Coordinator::Write::Events::HistoryMigrationPagePlannedV1.new(page_id:)
      ]
    )
  end
  let(:command) do
    Coordinator::Write::Commands::AdvanceHistoryMigration.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      migration_id:,
      page_id:,
      next_from_position: 10
    )
  end

  it "advances the planning cursor and closes the complete plan at the frozen upper bound" do
    decision = decider.call(snapshot:, page:, command:).value!

    expect(decision.outcome).to eq("plan_completed")
    expect(decision.plan.events.map(&:to_h)).to eq(
      [ { migration_id:, next_from_position: 10 }, { migration_id: } ]
    )
  end
end
