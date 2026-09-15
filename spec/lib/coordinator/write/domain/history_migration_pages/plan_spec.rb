# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::HistoryMigrationPages::Plan do
  subject(:decider) { described_class.new }

  let(:page_id) { SecureRandom.uuid_v7 }
  let(:state) do
    creation = Coordinator::Write::Domain::HistoryMigrationPages::Create.new.call(
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
    Coordinator::Write::Domain::HistoryMigrationPages::State.reduce(creation)
  end
  let(:command) do
    Coordinator::Write::Commands::PlanHistoryMigrationPage.new(
      command_id: SecureRandom.uuid_v7,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "history-migration"),
      page_id:,
      target_event_count: 5
    )
  end

  it "records the target count and planning barrier before application" do
    decision = decider.call(state:, command:).value!

    expect(decision.plan.events.map { _1.class.event_type }).to eq(
      %w[HistoryMigrationPageTargetEventCountRecorded HistoryMigrationPagePlanned]
    )
    planned = state
    decision.plan.events.each { |event| planned = planned.apply(event) }
    expect(planned).to be_planned
    expect(planned).not_to be_applied
    expect(decider.call(state: planned, command:).value!.to_h).to eq(outcome: "existing", plan: nil)
  end
end
