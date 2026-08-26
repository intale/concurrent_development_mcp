# frozen_string_literal: true

RSpec.describe Coordinator::Container do
  it "memoizes shared infrastructure contracts resolved through Zeitwerk" do
    expect(described_class["canonical_json"]).to equal(described_class["canonical_json"])
    expect(described_class["event_schema_registry"]).to equal(described_class["event_schema_registry"])
    expect(described_class["stream_factory"]).to equal(described_class["stream_factory"])
  end

  it "builds command operations with their declared dependencies" do
    change_set_operation = described_class["operations.execute_create_change_set"]
    work_item_operation = described_class["operations.execute_create_work_item"]
    dependency_operation = described_class["operations.execute_declare_work_item_dependency"]
    activation_operation = described_class["operations.execute_activate_change_set"]
    readiness_operation = described_class["operations.execute_evaluate_work_item_readiness"]
    dependency_satisfaction_operation = described_class["operations.execute_satisfy_work_item_dependency"]
    change_set_completion_operation = described_class["operations.execute_complete_change_set"]
    acquisition_operation = described_class["operations.execute_acquire_work_item"]
    reservation_operation = described_class["operations.execute_reserve_write_set"]
    expansion_operation = described_class["operations.execute_expand_write_set"]
    renewal_operation = described_class["operations.execute_renew_lease_set"]
    release_operation = described_class["operations.execute_release_lease_set"]
    expiry_operation = described_class["operations.execute_expire_resource_lease"]
    guidance_operation = described_class["operations.execute_record_guidance"]
    interpretation_operation = described_class["operations.execute_propose_decision_interpretation"]
    adjudication_operation = described_class["operations.execute_adjudicate_decision_interpretation"]
    decision_activation_operation = described_class["operations.execute_activate_decision"]
    decision_correction_operation = described_class["operations.execute_correct_decision"]
    agent_choice_operation = described_class["operations.execute_record_agent_choice"]
    candidate_operation = described_class["operations.execute_submit_candidate"]
    candidate_impact_operation =
      described_class["operations.execute_submit_candidate_impact_surface"]
    skill_publish_operation = described_class["operations.execute_publish_skill_revision"]
    artifact_capture_operation = described_class["operations.execute_capture_development_artifact"]
    artifact_relation_operation = described_class["operations.execute_declare_development_artifact_relation"]
    operation_batch_operation = described_class["operations.execute_operation_batch_command"]
    operation_batch_process_manager = described_class["process_managers.operation_batch_runner"]
    impact_scan_start = described_class["operations.execute_start_agent_choice_impact_scan"]
    impact_scan_progress = described_class["operations.execute_progress_agent_choice_impact_scan"]
    impact_assessment = described_class["operations.execute_assess_agent_choice_decision_impact"]
    obligation_registry_start = described_class["operations.execute_start_candidate_impact_registry_sweep"]
    obligation_registry_progress = described_class["operations.execute_progress_candidate_impact_registry_sweep"]
    obligation_pair_start = described_class["operations.execute_start_candidate_impact_pair_scan"]
    obligation_pair_progress = described_class["operations.execute_progress_candidate_impact_pair_scan"]
    obligation_create = described_class["operations.execute_create_candidate_compatibility_obligation"]
    readiness_process_manager = described_class["process_managers.change_set_readiness"]
    build_progress_process_manager = described_class["process_managers.build_progress"]
    task_executor = described_class["process_managers.coordination_task_executor"]
    impact_process_manager = described_class["process_managers.agent_choice_decision_impact"]
    obligation_process_manager = described_class["process_managers.candidate_impact_obligation_policy"]
    subscription_manager = described_class["subscription_managers.process_managers"]
    subscription_set = described_class["subscription_sets.process_managers"]
    read_model_manager = described_class["subscription_managers.read_models"]
    read_model_set = described_class["subscription_sets.read_models"]
    operation_query = described_class["queries.operation_get"]
    context_query = described_class["queries.coord_context"]
    guidance_query = described_class["queries.guidance_get"]
    interpretation_query = described_class["queries.decision_interpretation_list"]
    decision_query = described_class["queries.decision_get"]
    agent_choice_query = described_class["queries.agent_choice_get"]
    agent_choice_impact_query = described_class["queries.agent_choice_impact_list"]
    candidate_get_query = described_class["queries.candidate_get"]
    candidate_list_query = described_class["queries.candidate_list"]
    candidate_impact_query = described_class["queries.candidate_impact_get"]
    repository_list_query = described_class["queries.repository_list"]
    skill_get_query = described_class["queries.skill_get"]
    skill_list_query = described_class["queries.skill_list"]
    skill_asset_get_query = described_class["queries.skill_asset_get"]
    artifact_get_query = described_class["queries.development_artifact_get"]
    artifact_content_get_query = described_class["queries.development_artifact_content_get"]
    artifact_relation_list_query = described_class["queries.development_artifact_relation_list"]
    artifact_locator_resolve_query =
      described_class["queries.development_artifact_locator_resolve"]
    artifact_list_query = described_class["queries.development_artifact_list"]
    operation_batch_query = described_class["queries.operation_batch_get"]
    verification_obligations_query = described_class["queries.verification_obligations_list"]
    task_submissions = %w[
      operations.submit_create_change_set_task
      operations.submit_create_work_item_task
      operations.submit_declare_work_item_dependency_task
      operations.submit_activate_change_set_task
      operations.submit_acquire_work_item_task
      operations.submit_reserve_write_set_task
      operations.submit_expand_write_set_task
      operations.submit_renew_lease_set_task
      operations.submit_release_lease_set_task
      operations.submit_record_guidance_task
      operations.submit_propose_decision_interpretation_task
      operations.submit_adjudicate_decision_interpretation_task
      operations.submit_activate_decision_task
      operations.submit_correct_decision_task
      operations.submit_record_agent_choice_task
      operations.submit_candidate_task
      operations.submit_candidate_impact_surface_task
      operations.submit_publish_skill_revision_task
      operations.submit_create_skill_publish_batch_task
      operations.submit_capture_development_artifact_task
      operations.submit_declare_development_artifact_relation_task
      operations.submit_create_development_artifact_capture_batch_task
      operations.submit_create_development_artifact_relation_declare_batch_task
      operations.submit_cancel_operation_batch_task
    ].map { described_class[_1] }
    tasks_extension = described_class["mcp.tasks.extension"]
    mcp_transport = described_class["mcp.transport"]

    expect(change_set_operation).to be_a(Coordinator::Write::Operations::ExecuteCreateChangeSet)
    expect(work_item_operation).to be_a(Coordinator::Write::Operations::ExecuteCreateWorkItem)
    expect(dependency_operation).to be_a(Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency)
    expect(activation_operation).to be_a(Coordinator::Write::Operations::ExecuteActivateChangeSet)
    expect(readiness_operation).to be_a(Coordinator::Write::Operations::ExecuteEvaluateWorkItemReadiness)
    expect(dependency_satisfaction_operation).to be_a(
      Coordinator::Write::Operations::ExecuteSatisfyWorkItemDependency
    )
    expect(change_set_completion_operation).to be_a(
      Coordinator::Write::Operations::ExecuteCompleteChangeSet
    )
    expect(acquisition_operation).to be_a(Coordinator::Write::Operations::ExecuteAcquireWorkItem)
    expect(reservation_operation).to be_a(Coordinator::Write::Operations::ExecuteReserveWriteSet)
    expect(expansion_operation).to be_a(Coordinator::Write::Operations::ExecuteExpandWriteSet)
    expect(renewal_operation).to be_a(Coordinator::Write::Operations::ExecuteRenewLeaseSet)
    expect(release_operation).to be_a(Coordinator::Write::Operations::ExecuteReleaseLeaseSet)
    expect(expiry_operation).to be_a(Coordinator::Write::Operations::ExecuteExpireResourceLease)
    expect(guidance_operation).to be_a(Coordinator::Write::Operations::ExecuteRecordGuidance)
    expect(interpretation_operation).to be_a(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation
    )
    expect(adjudication_operation).to be_a(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation
    )
    expect(decision_activation_operation).to be_a(
      Coordinator::Write::Operations::ExecuteActivateDecision
    )
    expect(decision_correction_operation).to be_a(
      Coordinator::Write::Operations::ExecuteCorrectDecision
    )
    expect(agent_choice_operation).to be_a(
      Coordinator::Write::Operations::ExecuteRecordAgentChoice
    )
    expect(candidate_operation).to be_a(Coordinator::Write::Operations::ExecuteSubmitCandidate)
    expect(candidate_impact_operation).to be_a(
      Coordinator::Write::Operations::ExecuteSubmitCandidateImpactSurface
    )
    expect(skill_publish_operation).to be_a(
      Coordinator::Write::Operations::ExecutePublishSkillRevision
    )
    expect(artifact_capture_operation).to be_a(
      Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact
    )
    expect(artifact_relation_operation).to be_a(
      Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation
    )
    expect(operation_batch_operation).to be_a(
      Coordinator::Write::Operations::ExecuteOperationBatchCommand
    )
    expect(impact_scan_start).to be_a(
      Coordinator::Write::Operations::ExecuteStartAgentChoiceImpactScan
    )
    expect(impact_scan_progress).to be_a(
      Coordinator::Write::Operations::ExecuteProgressAgentChoiceImpactScan
    )
    expect(impact_assessment).to be_a(
      Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact
    )
    expect(obligation_registry_start).to be_a(
      Coordinator::Write::Operations::ExecuteStartCandidateImpactRegistrySweep
    )
    expect(obligation_registry_progress).to be_a(
      Coordinator::Write::Operations::ExecuteProgressCandidateImpactRegistrySweep
    )
    expect(obligation_pair_start).to be_a(
      Coordinator::Write::Operations::ExecuteStartCandidateImpactPairScan
    )
    expect(obligation_pair_progress).to be_a(
      Coordinator::Write::Operations::ExecuteProgressCandidateImpactPairScan
    )
    expect(obligation_create).to be_a(
      Coordinator::Write::Operations::ExecuteCreateCandidateCompatibilityObligation
    )
    expect(readiness_process_manager).to be_a(Coordinator::Processes::ProcessManagers::ChangeSetReadiness)
    expect(build_progress_process_manager).to be_a(
      Coordinator::Processes::ProcessManagers::BuildProgress
    )
    expect(task_executor).to be_a(Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor)
    expect(operation_batch_process_manager).to be_a(
      Coordinator::Processes::ProcessManagers::OperationBatchRunner
    )
    expect(impact_process_manager).to be_a(
      Coordinator::Processes::ProcessManagers::AgentChoiceDecisionImpact
    )
    expect(obligation_process_manager).to be_a(
      Coordinator::Processes::ProcessManagers::CandidateImpactObligationPolicy
    )
    expect(subscription_manager).to be_a(PgEventstore::SubscriptionsManager)
    expect(subscription_set).to be_a(Coordinator::Processes::Subscriptions::ProcessManagerSet)
    expect(subscription_set.subscription_names).to eq(
      [
        "agent-choice-decision-impact-v1",
        "build-progress-v1",
        "candidate-impact-obligation-policy-v1",
        "change-set-readiness-v1",
        "coordination-task-executor-v1",
        "lease-expiry-scheduler-v1",
        "operation-batch-runner-v1",
        "release-set-lifecycle-v1",
        "verification-obligation-validity-v1"
      ]
    )
    expect(read_model_manager).to be_a(PgEventstore::SubscriptionsManager)
    expect(read_model_set).to be_a(Coordinator::Read::Subscriptions::ReadModelSet)
    expect(read_model_set.subscription_names).to eq(
      [
        "agent-choice-impacts-v1",
        "agent-choices-v1",
        "candidates-v1",
        "command-receipts-v1",
        "coord-context-v1",
        "decision-governance-v1",
        "decision-interpretations-v1",
        "development-artifacts-v2",
        "merge-snapshots-v1",
        "operation-batches-v1",
        "release-sets-v1",
        "repositories-v1",
        "skills-v1",
        "user-utterances-v1",
        "verification-obligations-v1"
      ]
    )
    expect(operation_query).to be_a(Coordinator::Read::Queries::OperationGet)
    expect(context_query).to be_a(Coordinator::Read::Queries::CoordContext)
    expect(guidance_query).to be_a(Coordinator::Read::Queries::GuidanceGet)
    expect(interpretation_query).to be_a(Coordinator::Read::Queries::DecisionInterpretationList)
    expect(decision_query).to be_a(Coordinator::Read::Queries::DecisionGet)
    expect(agent_choice_query).to be_a(Coordinator::Read::Queries::AgentChoiceGet)
    expect(agent_choice_impact_query).to be_a(Coordinator::Read::Queries::AgentChoiceImpactList)
    expect(candidate_get_query).to be_a(Coordinator::Read::Queries::CandidateGet)
    expect(candidate_list_query).to be_a(Coordinator::Read::Queries::CandidateList)
    expect(candidate_impact_query).to be_a(Coordinator::Read::Queries::CandidateImpactGet)
    expect(repository_list_query).to be_a(Coordinator::Read::Queries::RepositoryList)
    expect(skill_get_query).to be_a(Coordinator::Read::Queries::SkillGet)
    expect(skill_list_query).to be_a(Coordinator::Read::Queries::SkillList)
    expect(skill_asset_get_query).to be_a(Coordinator::Read::Queries::SkillAssetGet)
    expect(artifact_get_query).to be_a(Coordinator::Read::Queries::DevelopmentArtifactGet)
    expect(artifact_content_get_query).to be_a(
      Coordinator::Read::Queries::DevelopmentArtifactContentGet
    )
    expect(artifact_relation_list_query).to be_a(
      Coordinator::Read::Queries::DevelopmentArtifactRelationList
    )
    expect(artifact_locator_resolve_query).to be_a(
      Coordinator::Read::Queries::DevelopmentArtifactLocatorResolve
    )
    expect(artifact_list_query).to be_a(Coordinator::Read::Queries::DevelopmentArtifactList)
    expect(operation_batch_query).to be_a(Coordinator::Read::Queries::OperationBatchGet)
    expect(verification_obligations_query).to be_a(
      Coordinator::Read::Queries::VerificationObligationsList
    )
    expect(task_submissions).to all(
      be_a(Coordinator::Write::Operations::PrepareAndSubmitCoordinationTask)
    )
    expect(tasks_extension).to be_a(Coordinator::Mcp::Tasks::Extension)
    expect(mcp_transport).to be_a(Coordinator::Mcp::Tasks::StreamableHttpTransport)
  end

  it "provides constructor injection through Coordinator::Import" do
    probe_class = Class.new do
      include Coordinator::Import["canonical_json"]

      attr_reader :canonical_json
    end

    expect(probe_class.new.canonical_json).to equal(described_class["canonical_json"])
  end
end
