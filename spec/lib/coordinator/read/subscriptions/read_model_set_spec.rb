# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::ReadModelSet, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:context_registration) do
    Coordinator::Read::Subscriptions::CoordContext.new(
      handler: Coordinator::Read::Projectors::CoordContextV1.new,
      pull_interval: 0.2
    )
  end
  let(:receipt_registration) do
    Coordinator::Read::Subscriptions::CommandReceipts.new(
      handler: Coordinator::Read::Projectors::CommandReceiptsV1.new,
      pull_interval: 0.2
    )
  end
  let(:utterance_registration) do
    Coordinator::Read::Subscriptions::UserUtterances.new(
      handler: Coordinator::Read::Projectors::UserUtterancesV1.new,
      pull_interval: 0.2
    )
  end
  let(:interpretation_registration) do
    Coordinator::Read::Subscriptions::DecisionInterpretations.new(
      handler: Coordinator::Read::Projectors::DecisionInterpretationsV1.new,
      pull_interval: 0.2
    )
  end
  let(:decision_registration) do
    Coordinator::Read::Subscriptions::DecisionGovernance.new(
      handler: Coordinator::Read::Projectors::DecisionGovernanceV1.new,
      pull_interval: 0.2
    )
  end
  let(:agent_choice_registration) do
    Coordinator::Read::Subscriptions::AgentChoices.new(
      handler: Coordinator::Read::Projectors::AgentChoicesV1.new,
      pull_interval: 0.2
    )
  end
  let(:agent_choice_impact_registration) do
    Coordinator::Read::Subscriptions::AgentChoiceImpacts.new(
      handler: Coordinator::Read::Projectors::AgentChoiceImpactsV1.new,
      pull_interval: 0.2
    )
  end
  let(:candidate_registration) do
    Coordinator::Read::Subscriptions::Candidates.new(
      handler: Coordinator::Read::Projectors::CandidatesV1.new,
      pull_interval: 0.2
    )
  end
  let(:repository_registration) do
    Coordinator::Read::Subscriptions::Repositories.new(
      handler: Coordinator::Read::Projectors::RepositoriesV1.new,
      pull_interval: 0.2
    )
  end
  let(:skill_registration) do
    Coordinator::Read::Subscriptions::Skills.new(
      handler: Coordinator::Read::Projectors::SkillsV1.new,
      pull_interval: 0.2
    )
  end
  let(:development_artifact_registration) do
    Coordinator::Read::Subscriptions::DevelopmentArtifacts.new(
      handler: Coordinator::Read::Projectors::DevelopmentArtifactsV1.new,
      pull_interval: 0.2
    )
  end
  let(:operation_batch_registration) do
    Coordinator::Read::Subscriptions::OperationBatches.new(
      handler: Coordinator::Read::Projectors::OperationBatchesV2.new,
      pull_interval: 0.2
    )
  end
  let(:verification_obligation_registration) do
    Coordinator::Read::Subscriptions::VerificationObligations.new(
      handler: Coordinator::Read::Projectors::VerificationObligationsV1.new,
      pull_interval: 0.2
    )
  end
  let(:merge_snapshot_registration) do
    Coordinator::Read::Subscriptions::MergeSnapshots.new(
      handler: Coordinator::Read::Projectors::MergeSnapshotsV1.new,
      pull_interval: 0.2
    )
  end
  let(:release_set_registration) do
    Coordinator::Read::Subscriptions::ReleaseSets.new(
      handler: Coordinator::Read::Projectors::ReleaseSetsV1.new,
      pull_interval: 0.2
    )
  end

  it "stacks all fifteen unique durable subscriptions on one read-model manager" do
    subscription_set = build_set

    expect(subscription_set.subscription_names).to eq(
      [
        "agent-choice-impacts-v1",
        "agent-choices-v1",
        "candidates-v1",
        "command-receipts-v1",
        "coord-context-v2",
        "decision-governance-v1",
        "decision-interpretations-v1",
        "development-artifacts-v3",
        "merge-snapshots-v1",
        "operation-batches-v2",
        "release-sets-v1",
        "repositories-v1",
        "skills-v2",
        "user-utterances-v1",
        "verification-obligations-v1"
      ]
    )
    expect(context_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "coord-context-v2"
    )
    expect(context_registration.definition.event_types).to include(
      "WorkItemCandidateSelected",
      "AttemptCompleted",
      "WorkItemCompleted",
      "WorkItemDependencySatisfied",
      "ChangeSetCompleted"
    )
    expect(receipt_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "command-receipts-v1"
    )
    expect(utterance_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "user-utterances-v1"
    )
    expect(interpretation_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "decision-interpretations-v1"
    )
    expect(decision_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "decision-governance-v1"
    )
    expect(agent_choice_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "agent-choices-v1"
    )
    expect(agent_choice_impact_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "agent-choice-impacts-v1"
    )
    expect(candidate_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "candidates-v1"
    )
    expect(repository_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "repositories-v1"
    )
    expect(skill_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "skills-v2"
    )
    expect(development_artifact_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "development-artifacts-v3"
    )
    expect(operation_batch_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "operation-batches-v2"
    )
    expect(verification_obligation_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "verification-obligations-v1"
    )
    expect(merge_snapshot_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "merge-snapshots-v1"
    )
    expect(release_set_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "release-sets-v1"
    )
  end

  it "runs all projections through a real filtered pg_eventstore subscription set" do
    subscription_set = build_set

    begin
      subscription_set.start
      Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
        command_id: "cmd-subscription-100",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-SUB-100",
        goal: "Exercise both read models",
        acceptance_criteria: [ "Both subscriptions advance" ]
      ).value!
      Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
        command_id: "cmd-subscription-guidance",
        actor: { kind: "agent", id: "host-1" },
        message_id: "M-subscription",
        conversation_id: "C-subscription",
        source: "mcp_client",
        text: "Project attributed guidance evidence.",
        anchors: {
          repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        }
      ).value!
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:).call(
        InterpretationInput.build(
          command_id: "cmd-subscription-interpretation",
          interpretation_id: "I-subscription",
          source_message_id: "M-subscription",
          source_span: { start_character: 19, end_character: 27, text: "guidance" }
        )
      ).value!
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:).call(
        InterpretationInput.adjudication(
          command_id: "cmd-subscription-adjudication",
          source_message_id: "M-subscription",
          interpretation_id: "I-subscription"
        )
      ).value!
      activation = Coordinator::Write::Operations::ExecuteActivateDecision.new(event_store:).call(
        InterpretationInput.activation(
          command_id: "cmd-subscription-decision",
          decision_id: "D-subscription",
          interpretation_id: "I-subscription"
        )
      ).value!
      AgentChoiceScenario.record_no_policy_choice(
        prefix: "subscription-choice",
        repository_id: RepositoryScenario.repository_id("choice-subscription")
      )
      candidate = CandidateScenario.submit(prefix: "subscription-candidate", build_context: false)
      CandidateScenario.submit_impact(candidate)
      publish_skill
      artifact_id = capture_development_artifact
      batch_id = create_operation_batch
      release_set = ReleaseSetScenario.prepare(prefix: "read-model-subscription")
      obligation = CandidateObligationScenario.create_obligation(
        prefix: "read-model-subscription",
        required_evidence: [ "combined_tests" ]
      )
      claim = Coordinator::Write::Operations::ExecuteClaimVerificationObligation.new(
        event_store:
      ).call(
        command_id: "cmd-subscription-obligation-claim",
        actor: { kind: "agent", id: "agent-subscription" },
        obligation_id: obligation.fetch(:result).obligation_id,
        claim_duration_seconds: 300
      ).value!
      assessment = CandidateObligationScenario.submit_compatibility_assessment(
        created: obligation,
        claim: claim.data,
        command_id: "cmd-subscription-obligation-evidence"
      )

      wait_for(subscription_set, "coord-context-v2", minimum: 2)
      wait_for(subscription_set, "command-receipts-v1", minimum: 5)
      wait_for(subscription_set, "user-utterances-v1", minimum: 1)
      wait_for(subscription_set, "decision-interpretations-v1", minimum: 2)
      wait_for(subscription_set, "decision-governance-v1", minimum: 5)
      wait_for(subscription_set, "agent-choices-v1", minimum: 2)
      wait_for(subscription_set, "candidates-v1", minimum: 3)
      wait_for(subscription_set, "repositories-v1", minimum: 2)
      wait_for(subscription_set, "skills-v2", minimum: 1)
      wait_for(subscription_set, "development-artifacts-v3", minimum: 1)
      wait_for(subscription_set, "operation-batches-v2", minimum: 1)
      wait_for(subscription_set, "verification-obligations-v1", minimum: 4)
      wait_for(subscription_set, "merge-snapshots-v1", minimum: 1)
      wait_for(subscription_set, "release-sets-v1", minimum: 1)

      expect(Coordinator::Read::CoordContext.find("CS-SUB-100").document).to include(
        "schema" => "coord-context/v1"
      )
      expect(Coordinator::Read::CommandReceipt.find("cmd-subscription-100").tool_name).to eq(
        "change_set_create"
      )
      expect(Coordinator::Read::UserUtterance.find("M-subscription").policy_status).to eq(
        "evidence_only"
      )
      expect(Coordinator::Read::DecisionInterpretation.find("I-subscription")).to have_attributes(
        message_id: "M-subscription",
        policy_status: "proposal_only",
        lifecycle_status: "accepted"
      )
      expect(Coordinator::Read::DecisionDefinition.find("D-subscription")).to have_attributes(
        interpretation_id: "I-subscription",
        policy_status: "active"
      )
      expect(Coordinator::Read::DecisionSlotHead.find(activation.data.slot.slot_id)).to have_attributes(
        decision_id: "D-subscription"
      )
      expect(Coordinator::Read::DecisionPartitionHead.find("repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing")).to have_attributes(
        decision_id: "D-subscription",
        partition_revision: 0
      )
      expect(Coordinator::Read::AgentChoice.find("CHO-subscription-choice")).to have_attributes(
        choice_type: "testing.framework",
        observation_status: "accepted"
      )
      expect(Coordinator::Read::Candidate.find("CAN-subscription-candidate")).to have_attributes(
        attempt_id: "A-subscription-candidate",
        evidence_status: "attributed_unverified",
        impact_surface: include("evidence_status" => "attributed_unverified")
      )
      expect(Coordinator::Read::CandidateImpactKey.find_by!(
        candidate_id: "CAN-subscription-candidate",
        direction: "produces"
      ).impact_key).to eq("contract:payments-api:v2")
      expect(Coordinator::Read::Repository.find(
        RepositoryScenario.repository_id("ledger")
      )).to have_attributes(
        scope: RepositoryScenario.scope("ledger"),
        display_name: "Ledger test repository"
      )
      expect(Coordinator::Read::Repositories::Skills.new.fetch(
        name: "subscription-review",
        scope: "project:subscription"
      )).to have_attributes(revision: 1, instructions: "Inspect the live subscription result.")
      expect(Coordinator::Read::DevelopmentArtifact.find(artifact_id)).to have_attributes(
        title: "Subscription evidence"
      )
      expect(Coordinator::Read::OperationBatch.find(batch_id)).to have_attributes(
        target_tool: "skill_publish",
        total: 1
      )
      expect(Coordinator::Read::MergeSnapshot.find(
        "MS-read-model-subscription-1"
      )).to have_attributes(evidence_status: "attributed_unverified")
      expect(Coordinator::Read::ReleaseSet.find(
        release_set.dig(:input, :release_set_id)
      )).to have_attributes(status: "prepared")
      expect(Coordinator::Read::VerificationObligation.find(
        obligation.fetch(:result).obligation_id
      )).to have_attributes(
        change_set_id: obligation.dig(:pair, :ids, :change_set_id),
        status: "satisfied",
        claim_id: claim.data.claim_id,
        claimant_id: "agent-subscription",
        claim_fencing_token: 1,
        evidence_count: 1,
        passed_evidence_kinds: [ "combined_tests" ],
        missing_evidence_kinds: [],
        terminal_outcome: include(
          "obligation_id" => assessment.obligation_id,
          "outcome_digest" => a_string_starting_with("sha256:")
        )
      )
      expect(Coordinator::Read::VerificationObligationEvidenceItem.find(
        assessment.evidence_id
      )).to have_attributes(
        evidence_kind: "combined_tests",
        conclusion: "passed",
        event_id: assessment.evidence_event.event_id
      )
    ensure
      subscription_set.stop
    end
  end

  def build_set
    manager = PgEventstore.subscriptions_manager(
      subscription_set: described_class::SET_NAME
    )
    described_class.new(
      manager:,
      registrations: [
        context_registration,
        receipt_registration,
        utterance_registration,
        interpretation_registration,
        decision_registration,
        agent_choice_registration,
        agent_choice_impact_registration,
        candidate_registration,
        repository_registration,
        skill_registration,
        development_artifact_registration,
        operation_batch_registration,
        verification_obligation_registration,
        merge_snapshot_registration,
        release_set_registration
      ]
    )
  end

  def publish_skill
    Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:).call(
      command_id: "cmd-subscription-skill",
      actor: { kind: "agent", id: "agent-subscription" },
      name: "subscription-review",
      scope: "project:subscription",
      expected_revision: 0,
      description: "Review live subscription evidence",
      instructions: "Inspect the live subscription result.",
      assets: []
    ).value!
  end

  def capture_development_artifact
    Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:).call(
      command_id: "cmd-subscription-artifact",
      actor: { kind: "agent", id: "agent-subscription" },
      scope: "project:subscription",
      title: "Subscription evidence",
      kind: "verification_evidence",
      labels: %w[live subscription],
      content: {
        encoding: "utf-8",
        media_type: "text/plain",
        text: "all registrations observed\n"
      },
      source: {
        kind: "generated",
        locator: "spec/read-model-set",
        revision: nil,
        observed_at: "2026-08-28T06:30:00.000000Z",
        collector: "rspec/v1"
      }
    ).value!.data.artifact_id
  end

  def create_operation_batch
    batch_id = SecureRandom.uuid_v7
    command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
      command_id: "cmd-subscription-batch",
      actor: { kind: "agent", id: "agent-subscription" },
      batch_id:,
      items: [
        {
          command_id: "cmd-subscription-batch-item",
          actor: { kind: "agent", id: "agent-subscription" },
          name: "subscription-batch-skill",
          scope: "project:subscription",
          expected_revision: 0,
          description: "Exercise the Batch projection",
          instructions: "Project the accepted Batch.",
          assets: []
        }
      ]
    ).value!
    Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:).call_command(
      command
    ).value!
    batch_id
  end

  def wait_for(subscription_set, subscription_name, minimum:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    until subscription_set.processed_event_count(subscription_name) >= minimum
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "#{subscription_name} did not process #{minimum} events within 30 seconds"
      end

      sleep 0.05
    end
  end
end
