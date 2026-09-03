# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Subscriptions::SetFactory do
  it "creates independent process-manager sets from the production registrations" do
    factory = Coordinator::Container["subscription_set_factories.process_managers"]

    first = factory.call
    second = factory.call

    expect(first).to be_a(Coordinator::Processes::Subscriptions::ProcessManagerSet)
    expect(second).to be_a(Coordinator::Processes::Subscriptions::ProcessManagerSet)
    expect(first).not_to equal(second)
    expect(first.subscription_names).to eq(second.subscription_names)
  end

  it "creates independent read-model sets from the production registrations" do
    factory = Coordinator::Container["subscription_set_factories.read_models"]

    first = factory.call
    second = factory.call

    expect(first).to be_a(Coordinator::Read::Subscriptions::ReadModelSet)
    expect(second).to be_a(Coordinator::Read::Subscriptions::ReadModelSet)
    expect(first).not_to equal(second)
    expect(first.subscription_names).to eq(second.subscription_names)
  end

  it "creates independent Task-result sets from the production registrations" do
    factory = Coordinator::Container["subscription_set_factories.task_results"]

    first = factory.call
    second = factory.call

    expect(first).to be_a(Coordinator::Read::Subscriptions::TaskResultSet)
    expect(second).to be_a(Coordinator::Read::Subscriptions::TaskResultSet)
    expect(first).not_to equal(second)
    expect(first.subscription_names).to eq(second.subscription_names)
  end
end
