# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::RepositoriesV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registrar) { Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:) }
  let(:catalog) { Coordinator::Read::Repositories::RepositoryCatalog.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }

  it "projects an immutable registration idempotently with complete source attribution" do
    event = register_repository

    projector.call(event)
    projector.call(event)

    item = catalog.page(query(scope: "project:alpha")).items.sole
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
      catalog.page(query(scope: "project:alpha"), repository_key: "alpha").items.sole.repository_id
    ).to eq(repository_id)
  end

  it "can replay independently both over its existing row and from an empty projection" do
    event = register_repository
    projector.call(event)

    processed_events.delete_all
    projector.call(event)
    expect(Coordinator::Read::Repository.count).to eq(1)
    expect(processed_events.count).to eq(1)

    Coordinator::Read::Repository.delete_all
    processed_events.delete_all
    projector.call(event)

    expect(catalog.page(query(scope: "project:alpha")).items.sole.repository_id).to eq(repository_id)
    expect(processed_events.count).to eq(1)
  end

  def register_repository
    result = registrar.call(
      command_id: "cmd-project-repository-alpha",
      actor: { kind: "agent", id: "agent-repository" },
      repository_id:,
      scope: "project:alpha",
      repository_key: "alpha",
      display_name: "Alpha",
      paths: [ "/client/alpha" ],
      remotes: [ "https://example.test/alpha.git" ]
    )
    expect(result).to be_success

    event_store.read(
      Coordinator::Write::StreamFactory.new.repository(repository_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "RepositoryRegistered" ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
  end

  def query(scope:)
    Coordinator::Read::RepositoryListQueryV1.new(
      scope:,
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
