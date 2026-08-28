# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::AcquisitionEventPlan do
  subject(:contract) { described_class.new }

  let(:snapshot) do
    Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      object_format: "sha1",
      commit_oid: "0123456789abcdef0123456789abcdef01234567"
    )
  end
  let(:command) do
    Coordinator::Write::Commands::AcquireWorkItem.new(
      command_id: "cmd-300",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [ snapshot ]
    )
  end
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:plan) do
    result = Coordinator::Write::Domain::WorkItems::Acquire.new.call(
      change_set_state: Coordinator::Write::Domain::ChangeSets::State.new(
        change_set_id: "CS-100",
        goal: "Coordinate billing",
        status: "active",
        acceptance_criteria: [ "No duplicate ownership" ],
        work_item_ids: [ "W-200" ],
        dependencies: []
      ),
      work_item_state: Coordinator::Write::Domain::WorkItems::State.new(
        work_item_id: "W-200",
        change_set_id: "CS-100",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        goal: "Implement capture validation",
        acceptance_criteria: [ "The work is verifiable" ],
        status: "ready"
      ),
      attempt_state: Coordinator::Write::Domain::Attempts::State.initial,
      command:,
      occurred_at: "2026-08-20T14:20:00.000000Z"
    )
    result.value!
  end

  it "accepts the complete ordered command-owned event plan" do
    result = contract.call(
      plan:,
      command:,
      work_item_stream: streams.work_item("W-200"),
      attempt_stream: streams.attempt("A-300")
    )

    expect(result).to be_success
  end

  it "rejects a reordered plan before any append" do
    reordered = Coordinator::Write::Domain::EventPlan.new(writes: plan.writes.reverse)
    result = contract.call(
      plan: reordered,
      command:,
      work_item_stream: streams.work_item("W-200"),
      attempt_stream: streams.attempt("A-300")
    )

    expect(result.errors.to_h).to include(:plan)
  end

  it "rejects an object format inconsistent with the Git OID length" do
    inconsistent_snapshot = Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      object_format: "sha256",
      commit_oid: "0123456789abcdef0123456789abcdef01234567"
    )
    inconsistent_command = Coordinator::Write::Commands::AcquireWorkItem.new(
      command.to_h.merge(base_snapshots: [ inconsistent_snapshot ])
    )
    inconsistent_plan = Coordinator::Write::Domain::EventPlan.new(
      writes: plan.writes.map do |write|
        if write.event.is_a?(Coordinator::Write::Events::AttemptAuthorizedV1)
          Coordinator::Write::Domain::EventWrite.new(
            stream: write.stream,
            event: Coordinator::Write::Events::AttemptAuthorizedV1.new(
              write.event.to_h.merge(base_snapshots: [ inconsistent_snapshot ])
            )
          )
        else
          write
        end
      end
    )

    result = contract.call(
      plan: inconsistent_plan,
      command: inconsistent_command,
      work_item_stream: streams.work_item("W-200"),
      attempt_stream: streams.attempt("A-300")
    )

    expect(result.errors.to_h).to include(:plan)
  end
end
