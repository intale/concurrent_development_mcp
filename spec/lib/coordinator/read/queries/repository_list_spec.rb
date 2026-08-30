# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::RepositoryList, :read_model do
  subject(:query) { described_class.new }

  REPOSITORY_LIST_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000001
    018f0f4d-4e45-7abc-8def-000000000002
    018f0f4d-4e45-7abc-8def-000000000003
    018f0f4d-4e45-7abc-8def-000000000004
  ].freeze

  it "applies an exact scope and pages in deterministic Repository-ID order" do
    REPOSITORY_LIST_IDS.each_with_index do |repository_id, index|
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "repository-#{index}",
        scope: index == 3 ? "project:other" : "project:alpha"
      )
    end

    first = query.call(scope: "project:alpha", limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true, next_repository_id: REPOSITORY_LIST_IDS.fetch(1))
    expect(first.items.map(&:repository_id)).to eq(REPOSITORY_LIST_IDS.first(2))

    second = query.call(
      scope: "project:alpha",
      after_repository_id: first.next_repository_id,
      limit: 2
    ).value!.data.page
    expect(second).to have_attributes(has_more: false, next_repository_id: nil)
    expect(second.items.map(&:repository_id)).to eq([ REPOSITORY_LIST_IDS.fetch(2) ])

    other = query.call(scope: "project:other").value!.data.page
    expect(other.items.map(&:repository_id)).to eq([ REPOSITORY_LIST_IDS.fetch(3) ])

    exact_key = query.call(scope: "project:alpha", repository_key: "repository-1").value!.data.page
    expect(exact_key.items.map(&:repository_id)).to eq([ REPOSITORY_LIST_IDS.fetch(1) ])
    case_mismatch = query.call(scope: "project:alpha", repository_key: "Repository-1").value!.data.page
    expect(case_mismatch.items).to be_empty
  end

  it "serves every available row without consulting write-side state" do
    create(
      :coordinator_read_repository,
      repository_id: REPOSITORY_LIST_IDS.fetch(0),
      repository_key: "available",
      scope: "project:alpha"
    )

    result = query.call(scope: "project:alpha").value!

    expect(result).to have_attributes(status: "ok")
    expect(result.data.page.items.map(&:repository_id)).to eq([ REPOSITORY_LIST_IDS.fetch(0) ])
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
end
