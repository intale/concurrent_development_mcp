# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ResourcesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:resources) { Coordinator::Read::Repositories::Resources.new }
  let(:resource_id) { "018f0f4d-4e45-7abc-8def-000000000101" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:stream) { Coordinator::Write::StreamFactory.new.resource(resource_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects identity and lifecycle idempotently while serving the latest available state" do
    registered = resource_event(registered_payload, revision: 0, position: 100)
    bound = resource_event(bound_payload, revision: 1, position: 200, causation_id: registered.id)
    unbound = resource_event(unbound_payload, revision: 2, position: 300, causation_id: bound.id)

    projector.call(registered)
    projector.call(bound)
    projector.call(bound)

    available = resources.fetch(resource_id)
    expect(available).to have_attributes(
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      lifecycle_status: "current",
      unbinding_reason: nil,
      registered: have_attributes(event: have_attributes(event_id: registered.id)),
      latest_transition: have_attributes(event: have_attributes(event_id: bound.id))
    )

    projector.call(unbound)
    expect(resources.fetch(resource_id)).to have_attributes(
      lifecycle_status: "inactive",
      unbinding_reason: "removed",
      latest_transition: have_attributes(event: have_attributes(event_id: unbound.id))
    )
    expect(processed_events.count).to eq(3)
  end

  it "does not regress when an older transition is delivered after a newer one" do
    registered = resource_event(registered_payload, revision: 0, position: 100)
    bound = resource_event(bound_payload, revision: 1, position: 200, causation_id: registered.id)
    unbound = resource_event(unbound_payload, revision: 2, position: 300, causation_id: bound.id)

    projector.call(registered)
    projector.call(unbound)
    projector.call(bound)

    expect(resources.fetch(resource_id)).to have_attributes(
      lifecycle_status: "inactive",
      latest_transition: have_attributes(event: have_attributes(event_id: unbound.id))
    )
  end

  it "projects @2 identity facts using native event timestamps" do
    registered = resource_event_v2(
      Coordinator::Write::Events::ResourceIdentityV2::Registered.new(
        resource_id:, repository_id:, kind: "file", normalized_path: "app/models/projected.rb"
      ), revision: 0, position: 100, created_at: Time.utc(2026, 8, 30, 12)
    )
    bound = resource_event_v2(
      Coordinator::Write::Events::ResourceIdentityV2::Bound.new(
        resource_id:, repository_id:, kind: "file", normalized_path: "app/models/projected.rb"
      ), revision: 1, position: 200, created_at: Time.utc(2026, 8, 30, 12, 1)
    )

    projector.call(registered)
    projector.call(bound)
    record = Coordinator::Read::Resource.find(resource_id)

    expect(record.registered_at_domain).to eq(registered.created_at)
    expect(record.latest_transition_at_domain).to eq(bound.created_at)
    expect(record.updated_at).to eq(bound.created_at)
  end

  def registered_payload
    Coordinator::Write::Events::ResourceIdentityV1::Registered.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      registered_at: "2026-08-30T12:00:00.000000Z"
    )
  end

  def bound_payload
    Coordinator::Write::Events::ResourceIdentityV1::Bound.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      bound_at: "2026-08-30T12:01:00.000000Z"
    )
  end

  def unbound_payload
    Coordinator::Write::Events::ResourceIdentityV1::Unbound.new(
      resource_id:,
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      reason: "removed",
      unbound_at: "2026-08-30T12:02:00.000000Z"
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

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "resources",
      projection_version: 1
    )
  end
end
