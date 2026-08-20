# frozen_string_literal: true

RSpec.describe Coordinator::CommandInputDigest do
  subject(:digest) { described_class.new }

  let(:command) do
    Coordinator::Commands::CreateChangeSet.new(
      command_id: "cmd-100",
      actor: Coordinator::Commands::Actor.new(kind: "user", id: "user-1"),
      change_set_id: "CS-100",
      goal: "Add coordinated billing change",
      acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
    )
  end

  it "freezes every accepted semantic CreateChangeSet input into the digest document" do
    expect(digest.create_change_set_document(command)).to eq(
      Coordinator::CommandInputDocuments::CreateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: "cmd-100",
        tool_name: "change_set_create",
        input: Coordinator::CommandInputDocuments::CreateChangeSetInputV1.new(
          actor: Coordinator::CommandInputDocuments::ActorV1.new(
            actor_kind: "user",
            actor_id: "user-1"
          ),
          change_set_id: "CS-100",
          goal: "Add coordinated billing change",
          acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
        )
      )
    )
    expect(digest.create_change_set(command)).to eq(
      "sha256:444976af788427da1f4f4330cc799cb9b0c18497338da2bcd2acbdb05b32ca1c"
    )
  end

  it "changes when any accepted semantic field changes" do
    changed = Coordinator::Commands::CreateChangeSet.new(
      command.to_h.merge(goal: "A different goal")
    )

    expect(digest.create_change_set(changed)).not_to eq(digest.create_change_set(command))
  end

  it "freezes every accepted semantic CreateWorkItem input into a golden digest" do
    work_item_command = Coordinator::Commands::CreateWorkItem.new(
      command_id: "cmd-200",
      actor: Coordinator::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    )

    expect(digest.work_item_create_document(work_item_command)).to eq(
      Coordinator::CommandInputDocuments::CreateWorkItemV1.new(
        schema: "command-input/v1",
        command_id: "cmd-200",
        tool_name: "work_item_create",
        input: Coordinator::CommandInputDocuments::CreateWorkItemInputV1.new(
          actor: Coordinator::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "planner-1"
          ),
          change_set_id: "CS-100",
          work_item_id: "W-200",
          repository_id: "billing",
          goal: "Implement capture validation",
          acceptance_criteria: [ "Reject duplicate ownership" ]
        )
      )
    )
    expect(digest.work_item_create(work_item_command)).to eq(
      "sha256:eae762817e3077c7284917ed870ae60f97ad35ff1ac3680087dadd198e8efe5d"
    )
  end

  it "includes the complete typed dependency declaration in its golden digest" do
    dependency_command = Coordinator::Commands::DeclareWorkItemDependency.new(
      command_id: "cmd-230",
      actor: Coordinator::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    )

    expect(digest.work_item_dependency_declare_document(dependency_command)).to eq(
      Coordinator::CommandInputDocuments::DeclareWorkItemDependencyV1.new(
        schema: "command-input/v1",
        command_id: "cmd-230",
        tool_name: "work_item_dependency_declare",
        input: Coordinator::CommandInputDocuments::DeclareWorkItemDependencyInputV1.new(
          actor: Coordinator::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "planner-1"
          ),
          change_set_id: "CS-100",
          dependency_id: "DEP-1",
          producer_work_item_id: "W-100",
          consumer_work_item_id: "W-200",
          dependency_kind: "requires_candidate",
          required_output: nil
        )
      )
    )
    expect(digest.work_item_dependency_declare(dependency_command)).to eq(
      "sha256:ed3e6cad9dc37c0a8498d1e5c576f6c1e6c1b87e492ac091efc5463ae51a6df8"
    )
  end

  it "freezes the complete typed activation input into a golden digest" do
    activation_command = Coordinator::Commands::ActivateChangeSet.new(
      command_id: "cmd-250",
      actor: Coordinator::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100"
    )

    expect(digest.change_set_activate_document(activation_command)).to eq(
      Coordinator::CommandInputDocuments::ActivateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: "cmd-250",
        tool_name: "change_set_activate",
        input: Coordinator::CommandInputDocuments::ActivateChangeSetInputV1.new(
          actor: Coordinator::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "planner-1"
          ),
          change_set_id: "CS-100"
        )
      )
    )
    expect(digest.change_set_activate(activation_command)).to eq(
      "sha256:b4c83e9946432f74040fe1be7ae68be144dddec298bab8067113c61d19539e71"
    )
  end

  it "includes normalized repository evidence in the acquisition digest" do
    acquisition_command = Coordinator::Commands::AcquireWorkItem.new(
      command_id: "cmd-300",
      actor: Coordinator::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        Coordinator::RepositorySnapshotV1.new(
          repository_id: "billing",
          object_format: "sha1",
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        )
      ]
    )

    expect(digest.work_item_acquire_document(acquisition_command)).to eq(
      Coordinator::CommandInputDocuments::AcquireWorkItemV1.new(
        schema: "command-input/v1",
        command_id: "cmd-300",
        tool_name: "work_item_acquire",
        input: Coordinator::CommandInputDocuments::AcquireWorkItemInputV1.new(
          actor: Coordinator::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "agent-a"
          ),
          change_set_id: "CS-100",
          work_item_id: "W-200",
          attempt_id: "A-300",
          base_snapshots: [
            Coordinator::CommandInputDocuments::RepositorySnapshotV1.new(
              repository_id: "billing",
              object_format: "sha1",
              commit_oid: "0123456789abcdef0123456789abcdef01234567"
            )
          ]
        )
      )
    )
    expect(digest.work_item_acquire(acquisition_command)).to eq(
      "sha256:11382b77d0f6e7e226d4bb927aebeebfbf3fb1b61d929d2121f804449e3d16f0"
    )
  end
end
