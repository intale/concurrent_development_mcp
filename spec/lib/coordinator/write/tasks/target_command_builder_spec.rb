# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::TargetCommandBuilder do
  subject(:builder) { described_class.new }

  let(:actor) do
    Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a")
  end
  let(:digest) { Coordinator::Write::CommandInputDigest.new }

  it "round-trips every persisted command document into its exact typed command" do
    commands = [
      Coordinator::Write::Commands::CreateChangeSet.new(
        command_id: "cmd-task-build-1",
        actor:,
        change_set_id: "CS-task-build",
        goal: "Coordinate a typed Task",
        acceptance_criteria: [ "Every command survives persistence" ]
      ),
      Coordinator::Write::Commands::CreateWorkItem.new(
        command_id: "cmd-task-build-2",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        repository_id: "billing",
        goal: "Build the persisted command",
        acceptance_criteria: [ "The command remains typed" ]
      ),
      Coordinator::Write::Commands::DeclareWorkItemDependency.new(
        command_id: "cmd-task-build-3",
        actor:,
        change_set_id: "CS-task-build",
        dependency_id: "DEP-task-build",
        producer_work_item_id: "W-task-build-a",
        consumer_work_item_id: "W-task-build-b",
        dependency_kind: "requires_artifact",
        required_output: Coordinator::Write::RequiredOutput.new(
          kind: "artifact",
          key: "contract"
        )
      ),
      Coordinator::Write::Commands::ActivateChangeSet.new(
        command_id: "cmd-task-build-4",
        actor:,
        change_set_id: "CS-task-build"
      ),
      Coordinator::Write::Commands::AcquireWorkItem.new(
        command_id: "cmd-task-build-5",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        attempt_id: "ATT-task-build",
        base_snapshots: [
          Coordinator::Write::RepositorySnapshotV1.new(
            repository_id: "billing",
            object_format: "sha1",
            commit_oid: "a" * 40
          )
        ]
      )
    ]

    rebuilt = commands.map { builder.call(digest.document(_1)) }

    expect(rebuilt).to eq(commands)
  end
end
