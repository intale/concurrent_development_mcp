# frozen_string_literal: true

RSpec.describe Coordinator::Write::CommandInputDigest do
  subject(:digest) { described_class.new }

  let(:command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-100",
      actor: Coordinator::Write::Commands::Actor.new(kind: "user", id: "user-1"),
      change_set_id: "CS-100",
      goal: "Add coordinated billing change",
      acceptance_criteria: [ "Two agents cannot own the same WorkItem" ]
    )
  end

  it "freezes every accepted semantic CreateChangeSet input into the digest document" do
    expect(digest.create_change_set_document(command)).to eq(
      Coordinator::Write::CommandInputDocuments::CreateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: "cmd-100",
        tool_name: "change_set_create",
        input: Coordinator::Write::CommandInputDocuments::CreateChangeSetInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
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
    changed = Coordinator::Write::Commands::CreateChangeSet.new(
      command.to_h.merge(goal: "A different goal")
    )

    expect(digest.create_change_set(changed)).not_to eq(digest.create_change_set(command))
  end

  it "freezes every accepted semantic CreateWorkItem input into a golden digest" do
    work_item_command = Coordinator::Write::Commands::CreateWorkItem.new(
      command_id: "cmd-200",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    )

    expect(digest.work_item_create_document(work_item_command)).to eq(
      Coordinator::Write::CommandInputDocuments::CreateWorkItemV1.new(
        schema: "command-input/v1",
        command_id: "cmd-200",
        tool_name: "work_item_create",
        input: Coordinator::Write::CommandInputDocuments::CreateWorkItemInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
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
    dependency_command = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command_id: "cmd-230",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    )

    expect(digest.work_item_dependency_declare_document(dependency_command)).to eq(
      Coordinator::Write::CommandInputDocuments::DeclareWorkItemDependencyV1.new(
        schema: "command-input/v1",
        command_id: "cmd-230",
        tool_name: "work_item_dependency_declare",
        input: Coordinator::Write::CommandInputDocuments::DeclareWorkItemDependencyInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
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
    activation_command = Coordinator::Write::Commands::ActivateChangeSet.new(
      command_id: "cmd-250",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100"
    )

    expect(digest.change_set_activate_document(activation_command)).to eq(
      Coordinator::Write::CommandInputDocuments::ActivateChangeSetV1.new(
        schema: "command-input/v1",
        command_id: "cmd-250",
        tool_name: "change_set_activate",
        input: Coordinator::Write::CommandInputDocuments::ActivateChangeSetInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
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
    acquisition_command = Coordinator::Write::Commands::AcquireWorkItem.new(
      command_id: "cmd-300",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id: "billing",
          object_format: "sha1",
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        )
      ]
    )

    expect(digest.work_item_acquire_document(acquisition_command)).to eq(
      Coordinator::Write::CommandInputDocuments::AcquireWorkItemV1.new(
        schema: "command-input/v1",
        command_id: "cmd-300",
        tool_name: "work_item_acquire",
        input: Coordinator::Write::CommandInputDocuments::AcquireWorkItemInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "agent-a"
          ),
          change_set_id: "CS-100",
          work_item_id: "W-200",
          attempt_id: "A-300",
          base_snapshots: [
            Coordinator::Write::CommandInputDocuments::RepositorySnapshotV1.new(
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

  it "freezes the lease-set identity and normalized additions in the expansion digest" do
    resource = Coordinator::Write::FileResourceNormalizer.new.call(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path: "app/models/invoice.rb",
      base_blob_oid: "b" * 40
    ).value!
    expansion_command = Coordinator::Write::Commands::ExpandWriteSet.new(
      command_id: "cmd-expand-300",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      lease_set_id: "01919191-9191-7191-8191-919191919191",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ resource ]
    )

    document = digest.write_set_expand_document(expansion_command)

    expect(document).to eq(
      Coordinator::Write::CommandInputDocuments::ExpandWriteSetV1.new(
        schema: "command-input/v1",
        command_id: "cmd-expand-300",
        tool_name: "write_set_expand",
        input: Coordinator::Write::CommandInputDocuments::ExpandWriteSetInputV1.new(
          actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
            actor_kind: "agent",
            actor_id: "agent-a"
          ),
          change_set_id: "CS-100",
          work_item_id: "W-200",
          attempt_id: "A-300",
          lease_set_id: "01919191-9191-7191-8191-919191919191",
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          base_commit_oid: "a" * 40,
          resources: [ Coordinator::Write::CommandInputDocuments::FileResourceV1.new(resource.to_h) ]
        )
      )
    )
    expect(digest.write_set_expand(expansion_command)).to match(/\Asha256:[0-9a-f]{64}\z/)
    expect(digest.call(expansion_command)).to eq(digest.write_set_expand(expansion_command))
  end

  it "binds Decision correction replay to the exact authoritative predecessor" do
    expected_head = Coordinator::Write::EventReference.new(
      event_id: "01900000-0000-7000-8000-000000000001",
      type: "DecisionActivated",
      stream_context: "HumanGuidance",
      stream_name: "Decision",
      stream_id: "D-1",
      stream_revision: 1
    )
    correction_command = Coordinator::Write::Commands::CorrectDecision.new(
      command_id: "cmd-correction-1",
      actor: Coordinator::Write::Commands::Actor.new(kind: "orchestrator", id: "guidance-host"),
      decision_id: "D-1",
      interpretation_id: "I-2",
      expected_head:,
      rationale: Coordinator::Write::Decisions::DecisionCorrectionRationaleV1.new(
        code: "normalization_corrected",
        summary: "Apply the accepted correction."
      )
    )

    document = digest.decision_correct_document(correction_command)
    changed = Coordinator::Write::Commands::CorrectDecision.new(
      correction_command.to_h.merge(
        expected_head: Coordinator::Write::EventReference.new(
          expected_head.to_h.merge(
            event_id: "01900000-0000-7000-8000-000000000002",
            type: "DecisionDefinitionCorrected",
            stream_revision: 2
          )
        )
      )
    )

    expect(document.input.expected_head.to_h).to eq(expected_head.to_h)
    expect(digest.decision_correct(correction_command)).to match(/\Asha256:[0-9a-f]{64}\z/)
    expect(digest.call(correction_command)).to eq(digest.decision_correct(correction_command))
    expect(digest.decision_correct(changed)).not_to eq(digest.decision_correct(correction_command))
  end

  it "freezes normalized Candidate submission evidence into a typed golden digest" do
    input = {
      command_id: "cmd-candidate-digest-1",
      actor: { kind: "agent", id: "agent-7" },
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-18",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      lease_set_id: "01919191-9191-7191-8191-919191919191",
      leases: [
        {
          resource_key_hash: "sha256:#{"1" * 64}",
          lease_id: "01919191-9191-7191-8191-919191919192",
          fencing_token: 3
        }
      ],
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          {
            status: "modified",
            old_path: "lib/example.rb",
            new_path: "lib/example.rb",
            old_blob_oid: "c" * 40,
            new_blob_oid: "d" * 40,
            old_mode: "100644",
            new_mode: "100644"
          }
        ]
      },
      build_context: {
        collector_version: "build-context-v1",
        inputs: [
          { kind: "runtime_version", path: ".ruby-version", blob_oid: "e" * 40 }
        ],
        environment: [
          { name: "RUBY_ENGINE", value: "ruby" }
        ],
        dependency_graph_digest: "sha256:#{"f" * 64}"
      }
    }
    candidate_command = Coordinator::Write::Operations::PrepareSubmitCandidate.new.call(input).value!
    document = digest.candidate_submit_document(candidate_command)

    expect(document).to be_a(Coordinator::Write::CommandInputDocuments::SubmitCandidateV1)
    expect(document.input.change_manifest).to be_a(
      Coordinator::Write::CommandInputDocuments::CandidateChangeManifestV1
    )
    expect(document.input.build_context).to be_a(
      Coordinator::Write::CommandInputDocuments::CandidateBuildContextV1
    )
    expect(digest.candidate_submit(candidate_command)).to eq(
      "sha256:3423ce8197c09b7cf0628988d8b6b92e7a8deaabbce1ff55cbf3679537685190"
    )
    expect(digest.call(candidate_command)).to eq(digest.candidate_submit(candidate_command))
  end
end
