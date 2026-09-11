# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::ReadModelSet do
  let(:context_registration) do
    Coordinator::Read::Subscriptions::CoordContext.new(
      handler: Coordinator::Container["projectors.coord_context_v1"],
      pull_interval: 0.2
    )
  end
  let(:utterance_registration) do
    Coordinator::Read::Subscriptions::UserUtterances.new(
      handler: Coordinator::Container["projectors.user_utterances_v1"],
      pull_interval: 0.2
    )
  end
  let(:interpretation_registration) do
    Coordinator::Read::Subscriptions::DecisionInterpretations.new(
      handler: Coordinator::Container["projectors.decision_interpretations_v1"],
      pull_interval: 0.2
    )
  end
  let(:decision_registration) do
    Coordinator::Read::Subscriptions::DecisionGovernance.new(
      handler: Coordinator::Container["projectors.decision_governance_v1"],
      pull_interval: 0.2
    )
  end
  let(:agent_choice_registration) do
    Coordinator::Read::Subscriptions::AgentChoices.new(
      handler: Coordinator::Container["projectors.agent_choices_v1"],
      pull_interval: 0.2
    )
  end
  let(:agent_choice_impact_registration) do
    Coordinator::Read::Subscriptions::AgentChoiceImpacts.new(
      handler: Coordinator::Container["projectors.agent_choice_impacts_v1"],
      pull_interval: 0.2
    )
  end
  let(:candidate_registration) do
    Coordinator::Read::Subscriptions::Candidates.new(
      handler: Coordinator::Container["projectors.candidates_v1"],
      pull_interval: 0.2
    )
  end

  let(:repository_registration) do
    Coordinator::Read::Subscriptions::Repositories.new(
      handler: Coordinator::Container["projectors.repositories_v1"],
      pull_interval: 0.2
    )
  end
  let(:resource_registration) do
    Coordinator::Read::Subscriptions::Resources.new(
      handler: Coordinator::Container["projectors.resources_v1"],
      pull_interval: 0.2
    )
  end
  let(:skill_registration) do
    Coordinator::Read::Subscriptions::Skills.new(
      handler: Coordinator::Container["projectors.skills_v1"],
      pull_interval: 0.2
    )
  end
  let(:development_artifact_registration) do
    Coordinator::Read::Subscriptions::DevelopmentArtifacts.new(
      handler: Coordinator::Container["projectors.development_artifacts_v1"],
      pull_interval: 0.2
    )
  end
  let(:operation_batch_registration) do
    Coordinator::Read::Subscriptions::OperationBatches.new(
      handler: Coordinator::Container["projectors.operation_batches_v2"],
      pull_interval: 0.2
    )
  end
  let(:verification_obligation_registration) do
    Coordinator::Read::Subscriptions::VerificationObligations.new(
      handler: Coordinator::Container["projectors.verification_obligations_v1"],
      pull_interval: 0.2
    )
  end
  let(:merge_snapshot_registration) do
    Coordinator::Read::Subscriptions::MergeSnapshots.new(
      handler: Coordinator::Container["projectors.merge_snapshots_v1"],
      pull_interval: 0.2
    )
  end

  let(:release_set_registration) do
    Coordinator::Read::Subscriptions::ReleaseSets.new(
      handler: Coordinator::Container["projectors.release_sets_v1"],
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
        "coord-context-v6",
        "decision-governance-v1",
        "decision-interpretations-v1",
        "development-artifacts-v3",
        "merge-snapshots-v1",
        "operation-batches-v2",
        "release-sets-v1",
        "repositories-v1",
        "resources-v1",
        "skills-v3",
        "user-utterances-v1",
        "verification-obligations-v1"
      ]
    )
    expect(context_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "coord-context-v6"
    )
    expect(context_registration.definition.event_types).to include(
      "CandidateSubmitted",
      "WorkItemCandidateSelected",
      "AttemptCompleted",
      "WorkItemCompleted",
      "WorkItemDependencySatisfied",
      "ChangeSetCompleted"
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
    expect(resource_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "resources-v1"
    )
    expect(skill_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "skills-v3"
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

  def build_set
    manager = PgEventstore.subscriptions_manager(
      subscription_set: described_class::SET_NAME
    )
    described_class.new(
      manager:,
      registrations: [
        context_registration,
        utterance_registration,
        interpretation_registration,
        decision_registration,
        agent_choice_registration,
        agent_choice_impact_registration,
        candidate_registration,
        repository_registration,
        resource_registration,
        skill_registration,
        development_artifact_registration,
        operation_batch_registration,
        verification_obligation_registration,
        merge_snapshot_registration,
        release_set_registration
      ]
    )
  end
end
