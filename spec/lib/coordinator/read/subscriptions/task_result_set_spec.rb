# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::TaskResultSet do
  let(:receipt_registration) do
    Coordinator::Read::Subscriptions::CommandReceipts.new(
      handler: Coordinator::Container["projectors.command_receipts_v2"],
      pull_interval: 0.2
    )
  end

  it "isolates the Task-result projection from ordinary read models" do
    manager = PgEventstore.subscriptions_manager(
      subscription_set: described_class::SET_NAME
    )
    subscription_set = described_class.new(
      manager:,
      registrations: [ receipt_registration ]
    )

    expect(subscription_set.subscription_names).to eq([ "command-receipts-v2" ])
    expect(receipt_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-task-results-v1",
      subscription_name: "command-receipts-v2"
    )
  end
end
