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

  it "keeps the older view available while integration and verification lag, then converges in stream order" do
    prepared = ReleaseSetScenario.prepare(prefix: "projection-lifecycle")
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "projection-lifecycle")
    verification = ReleaseSetScenario.record_verification(
      prepared,
      integrations:,
      prefix: "projection-lifecycle"
    )
    query = Coordinator::Read::Queries::ReleaseSetGet.new
    projector = described_class.new
    projector.call(prepared.fetch(:event))

    lagging = query.call(release_set_id: prepared.dig(:input, :release_set_id)).value!
    expect(lagging.data.release_set).to have_attributes(
      status: "prepared",
      verification_status: "unverified",
      integrations: [],
      verifications: []
    )

    [ *integrations.map { _1.fetch(:event) }, verification.fetch(:event) ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    observed = query.call(release_set_id: prepared.dig(:input, :release_set_id)).value!
    expect(observed.data.release_set).to have_attributes(
      status: "verified",
      verification_status: "passed"
    )
    expect(observed.data.release_set.integrations.map(&:repository_id)).to eq(%w[billing ledger])
    expect(observed.data.release_set.verifications.map { _1.evidence.outcome }).to eq([ "passed" ])
  end
end
