# frozen_string_literal: true

RSpec.describe Coordinator::Write::ReleaseSets::CorrelationLoader, :event_store do
  subject(:loader) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "returns the immutable preparation trace correlation" do
    prepared = ReleaseSetScenario.prepare(prefix: "correlation-loader")

    expect(loader.call(prepared.dig(:input, :release_set_id))).to eq(
      prepared.fetch(:event).correlation_id
    )
  end

  it "returns nil for an unknown ReleaseSet" do
    expect(loader.call("REL-correlation-loader-missing")).to be_nil
  end
end
