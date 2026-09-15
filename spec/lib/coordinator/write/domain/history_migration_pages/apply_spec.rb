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
  let(:command) do
    Coordinator::Write::Commands::ApplyHistoryMigrationPage.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      page_id:,
      target_event_count: 5
    )
  end

  it "records only the target count and applied fact, then no-ops exact redelivery" do
    planned = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation)
    decision = decider.call(state: planned, command:).value!

    expect(decision.plan.events.map(&:to_h)).to eq(
      [ { page_id:, target_event_count: 5 }, { page_id: } ]
    )
    applied = Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation + decision.plan.events)
    expect(decider.call(state: applied, command:).value!.to_h).to eq(outcome: "existing", plan: nil)
  end
end
