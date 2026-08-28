# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::Acquire do
  subject(:decider) { described_class.new }

  let(:occurred_at) { "2026-08-20T14:20:00.000000Z" }
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
  let(:change_set_state) do
    Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_id: "CS-100",
      goal: "Coordinate billing",
      status: "active",
      acceptance_criteria: [ "No duplicate ownership" ],
      work_item_ids: [ "W-200" ],
      dependencies: []
    )
  end
  let(:work_item_state) do
    Coordinator::Write::Domain::WorkItems::State.new(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement capture validation",
      acceptance_criteria: [ "The work is verifiable" ],
      status: "ready"
    )
  end

  it "implements EXE-01-SUCCESS-01 as one ordered three-event command plan" do
    result = decider.call(
      change_set_state:,
      work_item_state:,
      attempt_state: Coordinator::Write::Domain::Attempts::State.initial,
      command:,
      occurred_at:
    )

    expect(result).to be_success
    expect(result.value!.writes.map { _1.stream.stream_name }).to eq([ "WorkItem", "Attempt", "Attempt" ])
    expect(result.value!.events).to eq(
      [
        Coordinator::Write::Events::WorkItemAcquiredV1.new(
          change_set_id: "CS-100",
          work_item_id: "W-200",
          attempt_id: "A-300",
          agent_id: "agent-a",
          acquired_at: occurred_at
        ),
        Coordinator::Write::Events::AttemptAuthorizedV1.new(
          attempt_id: "A-300",
          change_set_id: "CS-100",
          work_item_id: "W-200",
          agent_id: "agent-a",
          base_snapshots: [ snapshot ],
          authorized_at: occurred_at
        ),
        Coordinator::Write::Events::AttemptStartedV1.new(
          attempt_id: "A-300",
          change_set_id: "CS-100",
          work_item_id: "W-200",
          started_at: occurred_at
        )
      ]
    )
  end

  it "returns every frozen zero-event denial with deterministic precedence" do
    inactive = Coordinator::Write::Domain::ChangeSets::State.new(change_set_state.to_h.merge(status: "draft"))
    no_member = Coordinator::Write::Domain::ChangeSets::State.new(change_set_state.to_h.merge(work_item_ids: []))
    planned = Coordinator::Write::Domain::WorkItems::State.new(work_item_state.to_h.merge(status: "planned"))
    wrong_change_set = Coordinator::Write::Domain::WorkItems::State.new(
      work_item_state.to_h.merge(change_set_id: "CS-other")
    )
    active = Coordinator::Write::Domain::WorkItems::State.new(
      work_item_state.to_h.merge(status: "active", active_attempt_id: "A-other", active_agent_id: "agent-b")
    )
    existing_attempt = Coordinator::Write::Domain::Attempts::State.new(
      attempt_id: "A-300",
      change_set_id: "CS-other",
      work_item_id: "W-other",
      agent_id: "agent-b",
      base_snapshots: [ snapshot ],
      lease_set_id: nil,
      lease_repository_id: nil,
      lease_policy_version: nil,
      lease_resources: [],
      lease_reserved_at: nil,
      lease_renewed_at: nil,
      lease_expires_at: nil,
      lease_released_at: nil,
      status: "active"
    )
    wrong_repository = Coordinator::Write::Commands::AcquireWorkItem.new(
      command.to_h.merge(
        base_snapshots: [
          Coordinator::Write::RepositorySnapshotV1.new(
            snapshot.to_h.merge(repository_id: RepositoryScenario.repository_id("ledger"))
          )
        ]
      )
    )
    scenarios = [
      [ inactive, work_item_state, Coordinator::Write::Domain::Attempts::State.initial, command, :change_set_not_active ],
      [ no_member, work_item_state, Coordinator::Write::Domain::Attempts::State.initial, command, :change_set_not_active ],
      [ change_set_state, planned, Coordinator::Write::Domain::Attempts::State.initial, command, :work_item_not_ready ],
      [ change_set_state, wrong_change_set, Coordinator::Write::Domain::Attempts::State.initial, command, :work_item_not_ready ],
      [ change_set_state, active, Coordinator::Write::Domain::Attempts::State.initial, command, :work_item_unavailable ],
      [ change_set_state, work_item_state, existing_attempt, command, :attempt_already_exists ],
      [
        change_set_state,
        work_item_state,
        Coordinator::Write::Domain::Attempts::State.initial,
        wrong_repository,
        :repository_base_mismatch
      ],
      [
        change_set_state,
        work_item_state,
        Coordinator::Write::Domain::Attempts::State.initial,
        Coordinator::Write::Commands::AcquireWorkItem.new(command.to_h.merge(base_snapshots: [])),
        :repository_base_mismatch
      ]
    ]

    aggregate_failures do
      scenarios.each do |change_set, work_item, attempt, candidate_command, code|
        result = decider.call(
          change_set_state: change_set,
          work_item_state: work_item,
          attempt_state: attempt,
          command: candidate_command,
          occurred_at:
        )

        expect(result).to be_failure
        expect(result.failure.code).to eq(code)
      end
    end
  end
end
