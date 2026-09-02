# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::TargetCommandBuilder do
  subject(:builder) { described_class.new }

  let(:actor) do
    Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a")
  end
  let(:digest) { Coordinator::Write::CommandInputDigest.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }

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
        repository_id:,
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
            repository_id:,
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
        repository_id:,
        base_commit_oid: "a" * 40,
        resources: [
          Coordinator::Write::ResourceLeaseTargetV1.new(
            resource_id: "0198e03a-d112-7000-8000-000000000006",
            base_blob_oid: "b" * 40,
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
        repository_id:,
        base_commit_oid: "a" * 40,
        resources: [
          Coordinator::Write::ResourceLeaseTargetV1.new(
            resource_id: "0198e03a-d112-7000-8000-000000000007",
            base_blob_oid: "c" * 40,
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
          Coordinator::Write::LeaseRenewalReferenceV2.new(
            resource_id: "0198e03a-d112-7000-8000-000000000007",
            lease_id: "0198e03a-d112-7000-8000-000000000008",
            fencing_token: 4
          )
        ],
        lease_duration_seconds: 600
      ),
      Coordinator::Write::Commands::ReleaseLeaseSet.new(
        command_id: "cmd-task-build-9",
        actor:,
        change_set_id: "CS-task-build",
        work_item_id: "W-task-build",
        attempt_id: "ATT-task-build",
        lease_set_id: "0198e03a-d112-7000-8000-000000000007",
        leases: [
          Coordinator::Write::LeaseReleaseReferenceV2.new(
            resource_id: "0198e03a-d112-7000-8000-000000000007",
            lease_id: "0198e03a-d112-7000-8000-000000000008",
            fencing_token: 4
          )
        ]
      ),
      Coordinator::Write::Operations::PrepareAdjudicateDecisionInterpretation.new.call(
        InterpretationInput.adjudication(
          command_id: "cmd-task-build-10",
          action: "request_clarification",
          clarification: InterpretationInput.clarification
        )
      ).value!,
      Coordinator::Write::Operations::PrepareActivateDecision.new.call(
        InterpretationInput.activation(command_id: "cmd-task-build-11")
      ).value!,
      Coordinator::Write::Operations::PrepareCorrectDecision.new.call(
        InterpretationInput.correction(
          command_id: "cmd-task-build-12",
          expected_head: {
            event_id: "0198e03a-d112-7000-8000-000000000012",
            type: "DecisionActivated",
            stream_context: "HumanGuidance",
            stream_name: "Decision",
            stream_id: "D-1",
            stream_revision: 1
          }
        )
      ).value!,
      Coordinator::Write::Commands::RecordAgentChoice.new(
        command_id: "cmd-task-build-13",
        actor:,
        choice_id: "CHO-task-build",
        choice_type: "testing.framework",
        selected: Coordinator::Write::AgentChoices::ChoiceOptionV1.new(
          option_id: "rspec",
          summary: "RSpec"
        ),
        alternatives: [
          Coordinator::Write::AgentChoices::ChoiceOptionV1.new(
            option_id: "minitest",
            summary: "Minitest"
          )
        ],
        reason_summary: "Use the testing framework selected for this Attempt.",
        context: agent_choice_query_context,
        decision_context: empty_decision_context
      ),
      Coordinator::Write::Operations::PrepareSubmitCandidateImpactSurface.new.call(
        command_id: "cmd-task-build-14",
        actor: { kind: "agent", id: "analyzer-a" },
        candidate_id: "CAN-task-build",
        repository_id:,
        head_commit_oid: "b" * 40,
        manifest_digest: "sha256:#{"a" * 64}",
        analyzer_version: "impact-v1",
        surface: {
          produces: [
            {
              impact_key: "dependency:rubygems:rails",
              before: "7.2",
              after: "8.0"
            }
          ],
          consumes: [],
          may_affect: [ { impact_key: "framework:rails:controller-lifecycle" } ],
          assumes: []
        }
      ).value!,
      Coordinator::Write::Operations::PrepareWaiveVerificationObligation.new.call(
        command_id: "cmd-task-build-15",
        actor: { kind: "user", id: "user-label" },
        obligation_id: "verification-obligation-v1:task-build",
        obligation_validity_input_digest: "sha256:#{"d" * 64}",
        reason: {
          code: "accepted_risk",
          summary: "User accepts this exact recorded coordination risk."
        }
      ).value!,
      Coordinator::Write::Operations::PrepareRegisterMergeSnapshot.new.call(
        command_id: "cmd-task-build-16",
        actor: { kind: "agent", id: "integrator-a" },
        merge_snapshot_id: "MS-task-build",
        repository_id:,
        target_branch: "main",
        target_base_commit_oid: "a" * 40,
        ordered_candidates: [
          { candidate_id: "CAN-task-build", head_commit_oid: "b" * 40 }
        ],
        merge_commit_oid: "9" * 40,
        producer: { name: "git-merge", version: "2.47.0" },
        run_id: "run-task-build",
        produced_at: "2026-08-24T15:30:00.000001Z"
      ).value!,
      Coordinator::Write::Commands::CorrectDevelopmentArtifactClassification.new(
        command_id: "cmd-task-build-17",
        actor:,
        observation_id: "018f0f4d-4e45-7abc-8def-000000000151",
        expected_revision: 1,
        title: "Correct classification",
        kind: "documentation",
        labels: %w[classification corrected],
        reason: "The original semantic classification was inaccurate."
      )
    ]

    rebuilt = commands.map do |command|
      submitted = Coordinator::Write::Events::CoordinationTaskSubmittedV2.new(
        task_id: "0198e03a-d112-7000-8000-000000000001",
        tool_name: digest.document(command).tool_name,
        command_id: command.command_id,
        command_input: digest.document(command),
        submitted_at: "2026-08-22T10:30:00.000000Z",
        ttl_ms: nil,
        poll_interval_ms: 500
      )
      reloaded = schemas.load(
        type: "CoordinationTaskSubmitted",
        schema_version: 2,
        data: JSON.parse(JSON.generate(submitted.to_h))
      )
      builder.call(reloaded.command_input)
    end

    expect(rebuilt).to eq(commands)
  end

  def agent_choice_query_context
    Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id:,
      change_set_id: "CS-task-build",
      work_item_id: "W-task-build",
      attempt_id: "ATT-task-build",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/invoice_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    )
  end

  def empty_decision_context
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new
      .call(agent_choice_query_context)
      .map do |partition|
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
    resolution = Coordinator::Write::DecisionContexts::ResultV1.new(
      effective_decision: nil,
      shadowed_decisions: [],
      conflict: nil,
      unresolved_decisions: [],
      unsupported_decisions: [],
      unsupported_dimensions: []
    )
    Coordinator::Write::DecisionContexts::Builder.new.call(
      context: agent_choice_query_context,
      observations:,
      resolution:,
      resolved_at: "2026-08-22T10:30:00.000000Z"
    )
  end
end
