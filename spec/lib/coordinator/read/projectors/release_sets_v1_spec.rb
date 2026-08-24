# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ReleaseSetsV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "serves lagging not-found content and converges idempotently without a freshness gate" do
    prepared = ReleaseSetScenario.prepare(prefix: "projection")
    query = Coordinator::Read::Queries::ReleaseSetGet.new

    lagging = query.call(release_set_id: prepared.dig(:input, :release_set_id)).value!
    expect(lagging.status).to eq("not_found")

    projector = described_class.new
    projector.call(prepared.fetch(:event))
    projector.call(prepared.fetch(:event))

    observed = query.call(release_set_id: prepared.dig(:input, :release_set_id)).value!
    expect(observed.status).to eq("ok")
    expect(observed.warnings).to include("This view may lag the authoritative event store.")
    expect(observed.data.release_set).to have_attributes(
      release_set_id: prepared.dig(:input, :release_set_id),
      change_set_id: "CS-release-projection",
      status: "prepared"
    )
    expect(observed.data.release_set.ordered_members.map(&:repository_id)).to eq(%w[billing ledger])
    expect(Coordinator::Read::ReleaseSet.count).to eq(1)
  end
end
