# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ResourcesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:resources) { Coordinator::Read::Repositories::Resources.new }
  let(:resource_id) { "018f0f4d-4e45-7abc-8def-000000000101" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:stream) { Coordinator::Write::StreamFactory.new.resource(resource_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "folds identity and lifecycle batches while serving the latest available projected state" do
    registered = resource_event(registered_payload, revision: 0, position: 100)
    bound = resource_event(bound_payload, revision: 1, position: 200, causation_id: registered.id)
    unbound = resource_event(unbound_payload, revision: 2, position: 300, causation_id: bound.id)

    projector.call([ registered, bound ])
    projector.call([ bound ])

    expect(resources.fetch(resource_id)).to have_attributes(
      repository_id:, kind: "file", normalized_path: "app/models/projected.rb", lifecycle_status: "current",
      unbinding_reason: nil, registered: have_attributes(event: have_attributes(event_id: registered.id)),
      latest_transition: have_attributes(event: have_attributes(event_id: bound.id))
    )

    projector.call([ unbound ])
    expect(resources.fetch(resource_id)).to have_attributes(
      lifecycle_status: "inactive", unbinding_reason: "removed",
      latest_transition: have_attributes(event: have_attributes(event_id: unbound.id))
    )
  end

  it "reapplies an ordered rewind without a ledger and converges on stable resource identity" do
    registered = resource_event(registered_payload, revision: 0, position: 100)
    bound = resource_event(bound_payload, revision: 1, position: 200, causation_id: registered.id)
    unbound = resource_event(unbound_payload, revision: 2, position: 300, causation_id: bound.id)
    batch = [ registered, bound, unbound ]

    2.times { projector.call(batch) }

    expect(Coordinator::Read::Resource.count).to eq(1)
    expect(resources.fetch(resource_id)).to have_attributes(lifecycle_status: "inactive", unbinding_reason: "removed")
  end

  it "preserves registration columns on a transition-only batch and clears an explicit reason" do
    row = create(:coordinator_read_resource, :inactive, resource_id:, repository_id:, normalized_path: "app/models/projected.rb")
    original = row.attributes.slice("registered_event", "registered_actor", "registered_markers", "registered_metadata")
    bound = resource_event(bound_payload, revision: 5, position: 500)

    projector.call([ bound ])

    expect(row.reload).to have_attributes(lifecycle_status: "current", unbinding_reason: nil)
    expect(row.attributes.slice(*original.keys)).to eq(original)
  end

  it "does not reset lifecycle columns when only the registration fact is replayed" do
    row = create(:coordinator_read_resource, :inactive, resource_id:, repository_id:, normalized_path: "app/models/projected.rb")

    projector.call([ resource_event(registered_payload, revision: 0, position: 100) ])

    expect(row.reload).to have_attributes(lifecycle_status: "inactive", unbinding_reason: "removed")
  end

  it "uses native event timestamps and the final delivered transition in a chunk" do
    registered = resource_event_v2(registered_payload, revision: 0, position: 100, created_at: Time.utc(2026, 10, 14, 12))
    unbound = resource_event_v2(unbound_payload, revision: 1, position: 200, created_at: Time.utc(2026, 10, 14, 12, 1))
    bound = resource_event_v2(bound_payload, revision: 2, position: 300, created_at: Time.utc(2026, 10, 14, 12, 2))

    projector.call([ registered, unbound, bound ])
    row = Coordinator::Read::Resource.find(resource_id)

    expect(row).to have_attributes(lifecycle_status: "current", unbinding_reason: nil, updated_at: bound.created_at)
    expect(row.registered_at_domain).to eq(registered.created_at)
    expect(row.latest_transition_at_domain).to eq(bound.created_at)
  end

  def registered_payload
    Coordinator::Write::Events::ResourceIdentityV2::Registered.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb"
    )
  end

  def bound_payload
    Coordinator::Write::Events::ResourceIdentityV2::Bound.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb"
    )
  end

  def unbound_payload
    Coordinator::Write::Events::ResourceIdentityV2::Unbound.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      reason: "removed"
    )
  end

  def resource_event(payload, revision:, position:, causation_id: nil)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-resource-projector-#{revision}",
      actor_id: "resource-projector-agent",
      policy_version: "resource-identity/v1",
      correlation_id:,
      causation_id:,
      markers: [ "resource:#{resource_id}", "repository:#{repository_id}" ]
    )
  end

  def resource_event_v2(payload, revision:, position:, created_at:)
    ProjectionEventFactory.build(
      payload:, stream:, stream_revision: revision, global_position: position,
      policy_version: "resource-identity/v1", correlation_id:, created_at:,
      markers: [ "resource:#{resource_id}", "repository:#{repository_id}" ]
    )
  end
end
