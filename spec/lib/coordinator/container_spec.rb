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
    acquisition_operation = described_class["operations.execute_acquire_work_item"]
    reservation_operation = described_class["operations.execute_reserve_write_set"]
    expansion_operation = described_class["operations.execute_expand_write_set"]
    renewal_operation = described_class["operations.execute_renew_lease_set"]
    release_operation = described_class["operations.execute_release_lease_set"]
    expiry_operation = described_class["operations.execute_expire_resource_lease"]
    guidance_operation = described_class["operations.execute_record_guidance"]
    interpretation_operation = described_class["operations.execute_propose_decision_interpretation"]
    adjudication_operation = described_class["operations.execute_adjudicate_decision_interpretation"]
    readiness_process_manager = described_class["process_managers.change_set_readiness"]
    task_executor = described_class["process_managers.coordination_task_executor"]
    subscription_manager = described_class["subscription_managers.process_managers"]
    subscription_set = described_class["subscription_sets.process_managers"]
    read_model_manager = described_class["subscription_managers.read_models"]
    read_model_set = described_class["subscription_sets.read_models"]
    operation_query = described_class["queries.operation_get"]
    context_query = described_class["queries.coord_context"]
    guidance_query = described_class["queries.guidance_get"]
    interpretation_query = described_class["queries.decision_interpretation_list"]
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
    ].map { described_class[_1] }
    tasks_extension = described_class["mcp.tasks.extension"]
    mcp_transport = described_class["mcp.transport"]

    expect(change_set_operation).to be_a(Coordinator::Write::Operations::ExecuteCreateChangeSet)
    expect(work_item_operation).to be_a(Coordinator::Write::Operations::ExecuteCreateWorkItem)
    expect(dependency_operation).to be_a(Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency)
    expect(activation_operation).to be_a(Coordinator::Write::Operations::ExecuteActivateChangeSet)
    expect(readiness_operation).to be_a(Coordinator::Write::Operations::ExecuteEvaluateWorkItemReadiness)
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
    expect(readiness_process_manager).to be_a(Coordinator::Processes::ProcessManagers::ChangeSetReadiness)
    expect(task_executor).to be_a(Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor)
    expect(subscription_manager).to be_a(PgEventstore::SubscriptionsManager)
    expect(subscription_set).to be_a(Coordinator::Processes::Subscriptions::ProcessManagerSet)
    expect(subscription_set.subscription_names).to eq(
      [ "change-set-readiness-v1", "coordination-task-executor-v1", "lease-expiry-scheduler-v1" ]
    )
    expect(read_model_manager).to be_a(PgEventstore::SubscriptionsManager)
    expect(read_model_set).to be_a(Coordinator::Read::Subscriptions::ReadModelSet)
    expect(read_model_set.subscription_names).to eq(
      [
        "command-receipts-v1",
        "coord-context-v1",
        "decision-interpretations-v1",
        "user-utterances-v1"
      ]
    )
    expect(operation_query).to be_a(Coordinator::Read::Queries::OperationGet)
    expect(context_query).to be_a(Coordinator::Read::Queries::CoordContext)
    expect(guidance_query).to be_a(Coordinator::Read::Queries::GuidanceGet)
    expect(interpretation_query).to be_a(Coordinator::Read::Queries::DecisionInterpretationList)
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
