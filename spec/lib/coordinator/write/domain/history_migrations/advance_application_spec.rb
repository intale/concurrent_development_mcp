# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::AdvanceApplication do
  subject(:decider) { described_class.new }

  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:page_id) { SecureRandom.uuid_v7 }
  let(:checkpoint_event) do
    PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "HistoryMigrationPlanCompleted")
  end
  let(:snapshot) do
    Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 9,
      page_size: 10,
      next_from_position: 10,
      plan_completed: true,
      application_dependency_wave: 0,
      application_next_from_position: 0,
      completed: false,
      abandoned: false,
      checkpoint_event:,
      latest_revision: 7
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
        Coordinator::Write::Events::HistoryMigrationPagePlannedV1.new(page_id:),
        Coordinator::Write::Events::HistoryMigrationPageDependencyWaveAppliedV1.new(
          page_id:,
          dependency_wave: 0,
          target_event_count: 12
        )
      ]
    )
  end
  let(:command) do
    Coordinator::Write::Commands::AdvanceHistoryMigrationApplication.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      migration_id:,
      page_id:,
      dependency_wave: 0,
      next_dependency_wave: 1,
      next_from_position: 0
    )
  end

  it "advances the application cursor only after the planned page has been applied" do
    decision = decider.call(snapshot:, page:, command:).value!

    expect(decision.outcome).to eq("advanced")
    expect(decision.plan.events.map(&:to_h)).to eq(
      [ { migration_id:, dependency_wave: 1, next_from_position: 0 } ]
    )
  end

  it "rejects application before the complete-plan barrier" do
    incomplete = snapshot.new(plan_completed: false)

    failure = decider.call(snapshot: incomplete, page:, command:).failure

    expect(failure.code).to eq(:history_migration_plan_required)
  end
end
