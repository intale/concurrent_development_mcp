# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::ProjectCatalog, :read_model do
  REPOSITORY_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000061
    018f0f4d-4e45-7abc-8def-000000000062
    018f0f4d-4e45-7abc-8def-000000000063
    018f0f4d-4e45-7abc-8def-000000000064
    018f0f4d-4e45-7abc-8def-000000000065
  ].freeze

  before do
    create_repository(0, scope: "project:alpha", name: "Alpha API", path: "/work/alpha/api")
    create_repository(1, scope: "project:alpha", name: "Billing", path: "/work/alpha/billing")
    create_repository(2, scope: "project:alpha", name: "Alpha Web", path: "/work/alpha/web")
    create_repository(3, scope: "project:beta", name: "Beta", path: "/special/search-target")
    create_repository(4, scope: "project:gamma", name: nil, path: "/work/gamma")
  end

  it "discovers exact Project scopes with bounded explicit Repository previews" do
    first = catalog.page(first: 2, repositories_first: 2, sort: "newest_first")

    expect(first.items.map(&:scope)).to eq(%w[project:alpha project:beta])
    expect(first).to have_attributes(has_more: true, next_scope: "project:beta")

    alpha = first.items.first
    expect(project_reference.decode(alpha.project_ref)).to eq("project:alpha")
    expect(alpha).to have_attributes(display_label: "project:alpha", repository_count: 3)
    expect(alpha.repositories.items.map(&:repository_id)).to eq(REPOSITORY_IDS.first(2))
    expect(alpha.repositories).to have_attributes(
      total_count: 3,
      has_more: true,
      next_repository_id: REPOSITORY_IDS.fetch(1)
    )

    beta = first.items.fetch(1)
    expect(beta).to have_attributes(display_label: "Beta", repository_count: 1)
    expect(beta.repositories.items.map(&:repository_id)).to eq([ REPOSITORY_IDS.fetch(3) ])

    second = catalog.page(
      first: 2,
      repositories_first: 2,
      sort: "newest_first",
      after_scope: first.next_scope,
      after_updated_at: first.next_updated_at
    )
    expect(second.items.map(&:scope)).to eq([ "project:gamma" ])
    expect(second).to have_attributes(has_more: false, next_scope: nil)
  end

  it "searches scope, Repository display name, and Repository path on the server" do
    by_scope = catalog.page(search: "ALPHA", sort: "newest_first")
    by_name = catalog.page(search: "billing", sort: "newest_first")
    by_path = catalog.page(search: "search-target", sort: "newest_first")

    expect(by_scope.items.map(&:scope)).to eq([ "project:alpha" ])
    expect(by_name.items.map(&:scope)).to eq([ "project:alpha" ])
    expect(by_path.items.map(&:scope)).to eq([ "project:beta" ])
  end

  it "supports stable oldest-event-time continuation" do
    first = catalog.page(first: 2, sort: "oldest_first")
    second = catalog.page(
      first: 2,
      sort: "oldest_first",
      after_scope: first.next_scope,
      after_updated_at: first.next_updated_at
    )

    expect(first.items.map(&:scope)).to eq(%w[project:gamma project:beta])
    expect(second.items.map(&:scope)).to eq([ "project:alpha" ])
  end

  it "resolves a Project reference and keyset-pages all Repository members" do
    project_ref = project_reference.encode(scope: "project:alpha")
    first = catalog.overview(project_ref:, repositories_first: 2)
    second = catalog.overview(
      project_ref:,
      repositories_first: 2,
      after_repository_id: first.repositories.next_repository_id,
      after_updated_at: first.repositories.next_updated_at
    )

    expect(first).to have_attributes(
      project_ref:,
      scope: "project:alpha",
      display_label: "project:alpha",
      repository_count: 3
    )
    expect(first.repositories.items.map(&:repository_id)).to eq(REPOSITORY_IDS.first(2))
    expect(first.repositories).to have_attributes(has_more: true, total_count: 3)
    expect(second.repositories.items.map(&:repository_id)).to eq([ REPOSITORY_IDS.fetch(2) ])
    expect(second.repositories).to have_attributes(has_more: false, next_repository_id: nil, total_count: 3)
  end

  it "returns no overview for an available projection with no matching exact scope" do
    project_ref = project_reference.encode(scope: "project:missing")

    expect(catalog.overview(project_ref:)).to be_nil
  end

  it "serves old available rows without a freshness gate" do
    overview = catalog.overview(project_ref: project_reference.encode(scope: "project:beta"))

    expect(overview.repositories.items.first.registered_at).to eq("2020-01-01T12:00:00.000000Z")
  end

  it "rejects invalid discovery input and invalid Project references through dry contracts" do
    expect { catalog.page(search: " padded") }
      .to raise_error(Coordinator::Read::Web::ProjectCatalogQueryError) do |error|
        expect(error.details).to have_key(:search)
      end
    expect { catalog.overview(project_ref: "not-a-project-reference") }
      .to raise_error(Coordinator::Read::Web::ProjectReference::InvalidReference)
    expect do
      catalog.overview(
        project_ref: project_reference.encode(scope: "project:alpha"),
        repositories_first: 101
      )
    end.to raise_error(Coordinator::Read::Web::ProjectCatalogQueryError) do |error|
      expect(error.details).to have_key(:repositories_first)
    end
  end

  def catalog
    @catalog ||= described_class.new
  end

  def project_reference
    @project_reference ||= Coordinator::Read::Web::ProjectReference.new
  end

  def create_repository(index, scope:, name:, path:)
    create(
      :coordinator_read_repository,
      repository_id: REPOSITORY_IDS.fetch(index),
      repository_key: "project-catalog-#{index}",
      scope:,
      display_name: name,
      paths: [ path ],
      registered_at_domain: Time.utc(2020, 1, 1, 12),
      created_at: Time.utc(2026, 8, 30, 12) - index.seconds,
      updated_at: Time.utc(2026, 8, 30, 12) - index.seconds
    )
  end
end
