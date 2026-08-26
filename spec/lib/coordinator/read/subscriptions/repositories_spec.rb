# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::Repositories do
  it "uses one unique read-model tuple and the exact Repository event filter" do
    definition = described_class::DEFINITION

    expect(definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "repositories-v1"
    )
    expect(definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentPlanning", stream_name: "Repository" } ],
        event_types: [ "RepositoryRegistered" ]
      }
    )
  end
end
