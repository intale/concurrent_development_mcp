# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ResourcesV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  let(:resources) { Coordinator::Read::Repositories::Resources.new }

  before { RepositoryScenario.register(event_store:) }

  it "projects identity and lifecycle idempotently without hiding an available stale view" do
    resource_id = resolve("cmd-resource-project-new", "app/models/projected.rb")
    registered, bound = resource_events(resource_id)

    projector.call(registered)
    projector.call(bound)
    projector.call(bound)

    current = resources.fetch(resource_id)
    expect(current).to have_attributes(
      repository_id:,
      kind: "file",
      normalized_path: "app/models/projected.rb",
      lifecycle_status: "current",
      unbinding_reason: nil,
      registered: have_attributes(event: have_attributes(event_id: registered.id)),
      latest_transition: have_attributes(event: have_attributes(event_id: bound.id))
    )

    remove(resource_id)
    available_while_lagging = resources.fetch(resource_id)
    expect(available_while_lagging).to have_attributes(lifecycle_status: "current")

    unbound = resource_events(resource_id).last
    projector.call(unbound)
    expect(resources.fetch(resource_id)).to have_attributes(
      lifecycle_status: "inactive",
      unbinding_reason: "removed",
      latest_transition: have_attributes(event: have_attributes(event_id: unbound.id))
    )
    expect(processed_events.count).to eq(3)
  end

  it "does not regress when an older transition is delivered after a newer one" do
    resource_id = resolve("cmd-resource-project-order-new", "app/models/ordered.rb")
    remove(resource_id)
    registered, bound, unbound = resource_events(resource_id)

    projector.call(registered)
    projector.call(unbound)
    projector.call(bound)

    expect(resources.fetch(resource_id)).to have_attributes(
      lifecycle_status: "inactive",
      latest_transition: have_attributes(event: have_attributes(event_id: unbound.id))
    )
  end

  def resolve(command_id, path)
    result = Coordinator::Write::Operations::ExecuteResolveResource.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: "resource-projector-agent" },
      repository_id:,
      kind: "file",
      path:
    )
    expect(result).to be_success
    result.value!.data.resource_id
  end

  def remove(resource_id)
    result = Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:).call(
      command_id: "cmd-resource-project-remove-#{resource_id}",
      actor: { kind: "agent", id: "resource-projector-agent" },
      resource_id:,
      reason: "removed"
    )
    expect(result).to be_success
  end

  def resource_events(resource_id)
    event_store.read(
      Coordinator::Write::StreamFactory.new.resource(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "resources",
      projection_version: 1
    )
  end
end
