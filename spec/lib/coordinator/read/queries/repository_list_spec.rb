# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::RepositoryList, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registrar) { Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:) }
  let(:projector) { Coordinator::Read::Projectors::RepositoriesV1.new }
  let(:repository_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000001
      018f0f4d-4e45-7abc-8def-000000000002
      018f0f4d-4e45-7abc-8def-000000000003
      018f0f4d-4e45-7abc-8def-000000000004
    ]
  end

  it "applies an exact scope and pages in deterministic Repository-ID order" do
    events = repository_ids.each_with_index.map do |repository_id, index|
      scope = index == 3 ? "project:other" : "project:alpha"
      register(repository_id:, scope:, index:)
    end
    events.each { projector.call(_1) }

    first = query.call(scope: "project:alpha", limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true, next_repository_id: repository_ids.fetch(1))
    expect(first.items.map(&:repository_id)).to eq(repository_ids.first(2))

    second = query.call(
      scope: "project:alpha",
      after_repository_id: first.next_repository_id,
      limit: 2
    ).value!.data.page
    expect(second).to have_attributes(has_more: false, next_repository_id: nil)
    expect(second.items.map(&:repository_id)).to eq([ repository_ids.fetch(2) ])

    other = query.call(scope: "project:other").value!.data.page
    expect(other.items.map(&:repository_id)).to eq([ repository_ids.fetch(3) ])

    exact_key = query.call(scope: "project:alpha", repository_key: "repository-1").value!.data.page
    expect(exact_key.items.map(&:repository_id)).to eq([ repository_ids.fetch(1) ])
    case_mismatch = query.call(scope: "project:alpha", repository_key: "Repository-1").value!.data.page
    expect(case_mismatch.items).to be_empty
  end

  it "serves the available projection while an unprojected registration exists" do
    available = register(repository_id: repository_ids.fetch(0), scope: "project:alpha", index: 0)
    register(repository_id: repository_ids.fetch(1), scope: "project:alpha", index: 1)
    projector.call(available)

    result = query.call(scope: "project:alpha").value!

    expect(result).to have_attributes(status: "ok")
    expect(result.data.page.items.map(&:repository_id)).to eq([ repository_ids.fetch(0) ])
    expect(result.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "requires an exact scope and returns typed invalid cursor and limit failures" do
    missing_scope = query.call({}).value!
    malformed = query.call(
      scope: "project:alpha",
      repository_key: "invalid key",
      after_repository_id: "repository-alpha",
      limit: 101
    ).value!

    expect(missing_scope).to have_attributes(status: "invalid")
    expect(missing_scope.data).to have_attributes(code: "invalid_input")
    expect(malformed).to have_attributes(status: "invalid")
    expect(malformed.data).to have_attributes(code: "invalid_input")
  end

  def register(repository_id:, scope:, index:)
    result = registrar.call(
      command_id: "cmd-repository-list-#{index}",
      actor: { kind: "agent", id: "agent-list" },
      repository_id:,
      scope:,
      repository_key: "repository-#{index}",
      display_name: "Repository #{index}",
      paths: [ "/client/repository-#{index}" ],
      remotes: []
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
end
