# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::TargetCommandBuilder do
  subject(:builder) { described_class.new }

  let(:actor) do
    Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a")
  end
  let(:digest) { Coordinator::Write::CommandInputDigest.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }

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
      ),
      Coordinator::Write::Commands::ReserveWriteSet.new(
        command_id: "cmd-task-build-6",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        attempt_id: "ATT-task-build",
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [
          Coordinator::Write::FileResourceV1.new(
            kind: "file",
            path: "app/models/invoice.rb",
            base_blob_oid: "b" * 40,
            resource_key: "repo:billing:file:app/models/invoice.rb",
            resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
            policy_version: "coordinator-resource-key/v1"
          )
        ],
        lease_duration_seconds: 300
      ),
      Coordinator::Write::Commands::ExpandWriteSet.new(
        command_id: "cmd-task-build-7",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        attempt_id: "ATT-task-build",
        lease_set_id: "0198e03a-d112-7000-8000-000000000007",
        repository_id: "billing",
        base_commit_oid: "a" * 40,
        resources: [
          Coordinator::Write::FileResourceV1.new(
            kind: "file",
            path: "app/services/tax.rb",
            base_blob_oid: "c" * 40,
            resource_key: "repo:billing:file:app/services/tax.rb",
            resource_key_hash: "sha256:f42d279fef1baf9ea3a532d1a89b57de451648cab46bba073a397a509382c67b",
            policy_version: "coordinator-resource-key/v1"
          )
        ]
      ),
      Coordinator::Write::Commands::RenewLeaseSet.new(
        command_id: "cmd-task-build-8",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        attempt_id: "ATT-task-build",
        lease_set_id: "0198e03a-d112-7000-8000-000000000007",
        leases: [
          Coordinator::Write::LeaseRenewalReferenceV1.new(
            resource_key_hash: "sha256:f42d279fef1baf9ea3a532d1a89b57de451648cab46bba073a397a509382c67b",
            lease_id: "0198e03a-d112-7000-8000-000000000008",
            fencing_token: 4
          )
        ],
        lease_duration_seconds: 600
      )
    ]

    rebuilt = commands.map do |command|
      submitted = Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(
        task_id: "0198e03a-d112-7000-8000-000000000001",
        tool_name: digest.document(command).tool_name,
        command_id: command.command_id,
        canonical_input_digest: digest.call(command),
        command_input: digest.document(command),
        submitted_at: "2026-08-22T10:30:00.000000Z",
        ttl_ms: nil,
        poll_interval_ms: 500
      )
      reloaded = schemas.load(
        type: "CoordinationTaskSubmitted",
        schema_version: 1,
        data: JSON.parse(JSON.generate(submitted.to_h))
      )
      builder.call(reloaded.command_input)
    end

    expect(rebuilt).to eq(commands)
  end
end
