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
    readiness_process_manager = described_class["process_managers.change_set_readiness"]
    subscription_manager = described_class["subscription_managers.process_managers"]
    subscription_set = described_class["subscription_sets.process_managers"]

    expect(change_set_operation).to be_a(Coordinator::Operations::ExecuteCreateChangeSet)
    expect(work_item_operation).to be_a(Coordinator::Operations::ExecuteCreateWorkItem)
    expect(dependency_operation).to be_a(Coordinator::Operations::ExecuteDeclareWorkItemDependency)
    expect(activation_operation).to be_a(Coordinator::Operations::ExecuteActivateChangeSet)
    expect(readiness_operation).to be_a(Coordinator::Operations::ExecuteEvaluateWorkItemReadiness)
    expect(acquisition_operation).to be_a(Coordinator::Operations::ExecuteAcquireWorkItem)
    expect(readiness_process_manager).to be_a(Coordinator::ProcessManagers::ChangeSetReadiness)
    expect(subscription_manager).to be_a(PgEventstore::SubscriptionsManager)
    expect(subscription_set).to be_a(Coordinator::Subscriptions::ProcessManagerSet)
    expect(subscription_set.subscription_names).to eq([ "change-set-readiness-v1" ])
  end

  it "provides constructor injection through Coordinator::Import" do
    probe_class = Class.new do
      include Coordinator::Import["canonical_json"]

      attr_reader :canonical_json
    end

    expect(probe_class.new.canonical_json).to equal(described_class["canonical_json"])
  end
end
