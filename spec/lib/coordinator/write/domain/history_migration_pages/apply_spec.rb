# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrationPages::Apply do
  subject(:decider) { described_class.new }

  let(:page_id) { SecureRandom.uuid_v7 }
  let(:creation) do
    Coordinator::Write::Domain::HistoryMigrationPages::Create.new.call(
      state: Coordinator::Write::Domain::HistoryMigrationPages::State.initial,
      command: Coordinator::Write::Commands::CreateHistoryMigrationPage.new(
        command_id: SecureRandom.uuid_v7,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
        migration_id: SecureRandom.uuid_v7,
        page_id:,
        from_position: 0,
        to_position: 2,
        source_event_count: 3
      )
    ).value!.plan.events
  end
  def command(dependency_wave:, target_event_count:)
    Coordinator::Write::Commands::ApplyHistoryMigrationPage.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      page_id:,
      dependency_wave:,
      target_event_count:
    )
  end

  it "records contiguous dependency-wave facts, then closes the fully applied page" do
    planning = Coordinator::Write::Domain::HistoryMigrationPages::Plan.new.call(
      state: Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation),
      command: Coordinator::Write::Commands::PlanHistoryMigrationPage.new(
        command_id: SecureRandom.uuid_v7,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
        page_id:,
        target_event_count: 5
      )
    ).value!.plan.events
    history = creation + planning
    [ 1, 2, 0, 2 ].each_with_index do |count, dependency_wave|
      current = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(history)
      wave_command = command(dependency_wave:, target_event_count: count)
      decision = decider.call(state: current, command: wave_command).value!
      expected = [
        { page_id:, dependency_wave:, target_event_count: count }
      ]
      expected << { page_id: } if dependency_wave == 3
      expect(decision.plan.events.map(&:to_h)).to eq(expected)
      history += decision.plan.events

      applied = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(history)
      expect(decider.call(state: applied, command: wave_command).value!.to_h).to eq(
        outcome: "existing",
        plan: nil
      )
    end

    expect(Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(history)).to be_applied
  end


  it "rejects an out-of-order wave and a final count that differs from the plan" do
    planning = Coordinator::Write::Domain::HistoryMigrationPages::Plan.new.call(
      state: Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation),
      command: Coordinator::Write::Commands::PlanHistoryMigrationPage.new(
        command_id: SecureRandom.uuid_v7,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
        page_id:,
        target_event_count: 5
      )
    ).value!.plan.events
    state = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation + planning)

    expect(decider.call(state:, command: command(dependency_wave: 1, target_event_count: 1)).failure.code)
      .to eq(:history_migration_page_conflict)

    history = creation + planning
    [ 1, 1, 1 ].each_with_index do |count, dependency_wave|
      state = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(history)
      history += decider.call(
        state:,
        command: command(dependency_wave:, target_event_count: count)
      ).value!.plan.events
    end
    state = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(history)
    expect(decider.call(state:, command: command(dependency_wave: 3, target_event_count: 1)).failure.code)
      .to eq(:history_migration_page_conflict)
  end
end
