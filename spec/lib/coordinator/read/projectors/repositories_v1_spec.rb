# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::RepositoriesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:catalog) { Coordinator::Read::Repositories::RepositoryCatalog.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }

  it "projects a concrete validated registration idempotently with source attribution" do
    event = registration_event

    projector.call(event)
    projector.call(event)

    item = catalog.page(query).items.sole
    expect(item).to have_attributes(
      repository_id:,
      scope: "project:alpha",
      display_name: "Alpha",
      paths: [ "/client/alpha" ],
      remotes: [ "https://example.test/alpha.git" ],
      registered: have_attributes(
        event: have_attributes(event_id: event.id, stream_revision: 0),
        actor: have_attributes(kind: "agent", id: "agent-repository"),
        global_position: event.global_position,
        causation_id: event.causation_id,
        correlation_id: event.correlation_id
      )
    )
    expect(Coordinator::Read::Repository.count).to eq(1)
    expect(processed_events.count).to eq(1)
    expect(
      catalog.page(query, repository_key: "alpha").items.sole.repository_id
    ).to eq(repository_id)
  end

  it "rolls back its idempotency claim when source identity is invalid" do
    event = registration_event(
      stream: Coordinator::Write::StreamFactory.new.repository(
        "018f0f4d-4e45-7abc-8def-000000000002"
      )
    )

    expect { projector.call(event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource,
      "Repository identity does not match its source stream"
    )
    expect(Coordinator::Read::Repository.count).to eq(0)
    expect(processed_events).to be_empty
  end

  def registration_event(stream: Coordinator::Write::StreamFactory.new.repository(repository_id))
    payload = Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id:,
      scope: "project:alpha",
      repository_key: "alpha",
      display_name: "Alpha",
      paths: [ "/client/alpha" ],
      remotes: [ "https://example.test/alpha.git" ],
      registered_at: "2026-08-30T12:00:00.000000Z"
    )
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: 0,
      global_position: 100,
      policy_version: "repository-registration/v1",
      actor_id: "agent-repository",
      markers: [ "repository:#{repository_id}", repository_key_marker ]
    )
  end

  def repository_key_marker
    Coordinator::Shared::CompoundMarkerBuilder.new.call(
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "scoped-repository-key",
        components: [ "scope:project:alpha", "repository-key:alpha" ]
      )
    ).marker
  end

  def query
    Coordinator::Read::RepositoryListQueryV1.new(
      scope: "project:alpha",
      after_repository_id: nil,
      limit: 20
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "repositories",
      projection_version: 1
    )
  end
end
