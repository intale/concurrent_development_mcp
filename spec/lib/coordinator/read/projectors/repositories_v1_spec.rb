# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::RepositoriesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:catalog) { Coordinator::Read::Repositories::RepositoryCatalog.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }

  it "projects a trusted registration idempotently with native source attribution" do
    event = registration_event
    2.times { projector.call([ event ]) }

    item = catalog.page(query).items.sole
    expect(item).to have_attributes(
      repository_id:, scope: "project:alpha", display_name: nil, paths: [], remotes: [],
      registered: have_attributes(
        event: have_attributes(event_id: event.id, stream_revision: 0),
        actor: have_attributes(kind: "agent", id: "agent-repository"),
        global_position: event.global_position, causation_id: event.causation_id, correlation_id: event.correlation_id
      )
    )
    expect(Coordinator::Read::Repository.count).to eq(1)
    expect(catalog.page(query, repository_key: "alpha").items.sole.repository_id).to eq(repository_id)
  end

  it "folds cohesive property facts in order and converges when the whole chunk is redelivered" do
    events = [
      registration_event_v2(revision: 0, position: 100),
      property_event(Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(repository_id:, display_name: "Alpha"), revision: 1, position: 101),
      property_event(Coordinator::Write::Events::RepositoryPathAddedV1.new(repository_id:, path: "/client/alpha"), revision: 2, position: 102),
      property_event(Coordinator::Write::Events::RepositoryRemoteAddedV1.new(repository_id:, remote: "https://example.test/alpha.git"), revision: 3, position: 103)
    ]

    2.times { projector.call(events) }

    expect(catalog.page(query).items.sole).to have_attributes(
      repository_id:, scope: "project:alpha", display_name: "Alpha",
      paths: [ "/client/alpha" ], remotes: [ "https://example.test/alpha.git" ]
    )
    expect(Coordinator::Read::Repository.find(repository_id).updated_at).to eq(events.last.created_at)
  end

  it "does not erase fields introduced by an earlier batch or reset collections on registration replay" do
    row = create(:coordinator_read_repository, repository_id:, scope: "project:alpha", display_name: "kept",
      paths: [ "/keep" ], remotes: [ "https://keep.test/repo" ])
    event = property_event(Coordinator::Write::Events::RepositoryPathAddedV1.new(repository_id:, path: "/new"), revision: 5, position: 105)

    projector.call([ event ])
    projector.call([ registration_event ])

    expect(row.reload).to have_attributes(display_name: "kept", paths: [ "/keep", "/new" ], remotes: [ "https://keep.test/repo" ])
  end

  it "folds add/remove membership by stable value without duplicate append on replay" do
    row = create(:coordinator_read_repository, repository_id:, paths: [ "/keep", "/remove" ])
    events = [
      property_event(Coordinator::Write::Events::RepositoryPathAddedV1.new(repository_id:, path: "/add"), revision: 5, position: 105),
      property_event(Coordinator::Write::Events::RepositoryPathRemovedV1.new(repository_id:, path: "/remove"), revision: 6, position: 106)
    ]

    2.times { projector.call(events) }

    expect(row.reload.paths).to eq([ "/keep", "/add" ])
  end

  it "writes a thousand property assignments as one update and no projection ledger queries" do
    row = create(:coordinator_read_repository, repository_id:)
    events = Array.new(1000) do |index|
      property_event(Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(repository_id:, display_name: "name-#{index}"),
        revision: index + 1, position: index + 1)
    end
    sql = []
    capture = ->(_name, _start, _finish, _id, payload) { sql << payload.fetch(:sql) }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { projector.call(events) }

    expect(sql.grep(/\AUPDATE\b/i).length).to eq(1)
    expect(sql.join("\n")).not_to include("processed_projection_events")
    expect(row.reload.display_name).to eq("name-999")
  end

  def registration_event(stream: Coordinator::Write::StreamFactory.new.repository(repository_id))
    payload = Coordinator::Write::Events::RepositoryRegisteredV2.new(
      repository_id:,
      scope: "project:alpha",
      repository_key: "alpha"
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

  def registration_event_v2(revision:, position:)
    payload = Coordinator::Write::Events::RepositoryRegisteredV2.new(
      repository_id:, scope: "project:alpha", repository_key: "alpha"
    )
    ProjectionEventFactory.build(
      payload:, stream: Coordinator::Write::StreamFactory.new.repository(repository_id),
      stream_revision: revision, global_position: position,
      policy_version: "repository-registration/v1", actor_id: "agent-repository",
      markers: [ "repository:#{repository_id}", repository_key_marker ]
    )
  end

  def property_event(payload, revision:, position:)
    ProjectionEventFactory.build(
      payload:, stream: Coordinator::Write::StreamFactory.new.repository(repository_id),
      stream_revision: revision, global_position: position,
      policy_version: "repository-registration/v1", actor_id: "agent-repository",
      markers: [ "repository:#{repository_id}" ]
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
end
