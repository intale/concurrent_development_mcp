# frozen_string_literal: true

RSpec.describe Coordinator::Web::Graphql::ProjectCursor do
  let(:scope) { "project:København/研发" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000071" }
  let(:updated_at) { "2026-09-01T12:00:00.000000Z" }

  it "round-trips a Project continuation bound to its search and sort" do
    cursor = described_class.encode_projects(
      after_scope: scope,
      after_updated_at: updated_at,
      search: "København",
      sort: "newest_first"
    )

    expect(
      described_class.decode_projects(cursor, search: "København", sort: "newest_first")
    ).to eq(after_scope: scope, after_updated_at: updated_at)
    expect do
      described_class.decode_projects(cursor, search: nil, sort: "newest_first")
    end.to raise_error(Coordinator::Web::Graphql::InvalidCursor, /does not match this query/)
    expect do
      described_class.decode_projects(cursor, search: "København", sort: "oldest_first")
    end.to raise_error(Coordinator::Web::Graphql::InvalidCursor, /does not match this query/)
  end

  it "rejects malformed, padded, and noncanonical Project cursors" do
    cursor = described_class.encode_projects(
      after_scope: scope,
      after_updated_at: updated_at,
      search: nil,
      sort: "oldest_first"
    )
    noncanonical = Base64.urlsafe_encode64(
      JSON.generate(
        "sort" => "oldest_first",
        "search" => nil,
        "after_scope" => scope,
        "after_updated_at" => updated_at,
        "kind" => "projects",
        "prefix" => described_class::PREFIX
      ),
      padding: false
    )

    [ "not-base64!", "#{cursor}=", noncanonical ].each do |invalid|
      expect do
        described_class.decode_projects(invalid, search: nil, sort: "oldest_first")
      end.to raise_error(Coordinator::Web::Graphql::InvalidCursor, /cursor is invalid/)
    end
  end

  it "round-trips Repository continuation only for the issuing Project reference" do
    cursor = described_class.encode_repositories(
      project_ref:,
      after_repository_id: repository_id,
      after_updated_at: updated_at
    )

    expect(described_class.decode_repositories(cursor, project_ref:)).to eq(
      after_repository_id: repository_id,
      after_updated_at: updated_at
    )

    other_ref = Coordinator::Read::Web::ProjectReference.new.encode(scope: "project:other")
    expect do
      described_class.decode_repositories(cursor, project_ref: other_ref)
    end.to raise_error(Coordinator::Web::Graphql::InvalidCursor, /does not match this project/)
  end
end
