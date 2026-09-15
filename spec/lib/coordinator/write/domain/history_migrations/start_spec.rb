# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrations::Start do
  subject(:decider) { described_class.new }

  let(:migration_id) { "01999999-9999-7999-8999-999999999999" }
  let(:command) do
    Coordinator::Write::Commands::StartHistoryMigration.new(
      command_id: "migration-start-1",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-agent"),
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 41,
      page_size: 1_000
    )
  end

  it "models creation, store selection, a frozen range, page policy, and start as cohesive facts" do
    decision = decider.call(
      state: Coordinator::Write::Domain::HistoryMigrations::State.initial,
      command:
    ).value!

    expect(decision.outcome).to eq("started")
    expect(decision.plan.events.map { _1.class.event_type }).to eq(
      %w[
        HistoryMigrationCreated
        HistoryMigrationSourceStoreSelected
        HistoryMigrationTargetStoreSelected
        HistoryMigrationSourceRangeFrozen
        HistoryMigrationPageSizeSelected
        HistoryMigrationStarted
      ]
    )
    expect(decision.plan.events.map(&:to_h)).to eq(
      [
        { migration_id: },
        { migration_id:, source_config_name: "default" },
        { migration_id:, target_config_name: "migration_target" },
        { migration_id:, source_upper_position: 41 },
        { migration_id:, page_size: 1_000 },
        { migration_id: }
      ]
    )
    expect(decision.plan.writes.map(&:stream).uniq.map(&:to_h)).to eq(
      [ { context: "CoordinatorMaintenance", stream_name: "HistoryMigration", stream_id: migration_id } ]
    )
  end

  it "returns an exact no-op and rejects a partial or different history" do
    events = decider.call(
      state: Coordinator::Write::Domain::HistoryMigrations::State.initial,
      command:
    ).value!.plan.events
    complete = Coordinator::Write::Domain::HistoryMigrations::State.reduce(events)

    existing = decider.call(state: complete, command:)
    conflict = decider.call(
      state: complete,
      command: command.class.new(command.attributes.merge(page_size: 500))
    )
    partial = decider.call(
      state: Coordinator::Write::Domain::HistoryMigrations::State.reduce(events.take(2)),
      command:
    )

    expect(existing.value!.to_h).to eq(outcome: "existing", plan: nil)
    expect(conflict.failure.code).to eq(:history_migration_conflict)
    expect(partial.failure.code).to eq(:history_migration_conflict)
  end

  it "rejects out-of-order history instead of silently reducing it" do
    expect do
      Coordinator::Write::Domain::HistoryMigrations::State.reduce([
        Coordinator::Write::Events::HistoryMigrationStartedV1.new(migration_id:)
      ])
    end.to raise_error(Coordinator::Write::InvalidHistoryMigrationHistory)
  end
end
