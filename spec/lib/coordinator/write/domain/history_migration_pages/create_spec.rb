# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrationPages::Create do
  subject(:decider) { described_class.new }

  let(:command) do
    Coordinator::Write::Commands::CreateHistoryMigrationPage.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      migration_id: SecureRandom.uuid_v7,
      page_id: SecureRandom.uuid_v7,
      from_position: 10,
      to_position: 19,
      source_event_count: 8
    )
  end

  it "creates one cohesive page plan and resolves its exact redelivery" do
    decision = decider.call(
      state: Coordinator::Write::Domain::HistoryMigrationPages::State.initial,
      command:
    ).value!

    expect(decision.outcome).to eq("created")
    expect(decision.plan.events.map { _1.class.event_type }).to eq(
      %w[
        HistoryMigrationPageCreated
        HistoryMigrationPageAddedToMigration
        HistoryMigrationPageSourceRangeSelected
        HistoryMigrationPageSourceEventCountRecorded
      ]
    )
    state = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(decision.plan.events)
    expect(decider.call(state:, command:).value!.to_h).to eq(outcome: "existing", plan: nil)
  end

  it "rejects an inverted range or reuse for different facts" do
    invalid = command.class.new(command.attributes.merge(from_position: 20, to_position: 19))
    expect(
      decider.call(state: Coordinator::Write::Domain::HistoryMigrationPages::State.initial, command: invalid)
        .failure.code
    ).to eq(:history_migration_page_invalid)

    events = decider.call(
      state: Coordinator::Write::Domain::HistoryMigrationPages::State.initial,
      command:
    ).value!.plan.events
    state = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(events)
    changed = command.class.new(command.attributes.merge(source_event_count: 7))
    expect(decider.call(state:, command: changed).failure.code).to eq(:history_migration_page_conflict)
  end
end
