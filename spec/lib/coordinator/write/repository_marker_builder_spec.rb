# frozen_string_literal: true

RSpec.describe Coordinator::Write::RepositoryMarkerBuilder do
  subject(:builder) { described_class.new }

  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }

  it "marks a file with its exact path and every strict ancestor overlap" do
    markers = builder.resource_event_markers(
      repository_id:,
      resource_kind: "file",
      resource_path: "app/models/user.rb"
    )

    expect(markers).to eq(
      [
        marker("resource-path", "app/models/user.rb"),
        marker("resource-overlap", "app"),
        marker("resource-overlap", "app/models")
      ]
    )
    expect(markers).to all(match(/\Acompound:resource-boundary:v1:sha256:[0-9a-f]{64}\z/))
  end

  it "adds a directory's own overlap marker so descendant queries select it symmetrically" do
    event_markers = builder.resource_event_markers(
      repository_id:,
      resource_kind: "directory",
      resource_path: "app/models"
    )
    boundary_markers = builder.resource_boundary_markers(
      repository_id:,
      resource_kind: "directory",
      resource_path: "app/models"
    )

    expect(event_markers).to eq(
      [
        marker("resource-path", "app/models"),
        marker("resource-overlap", "app"),
        marker("resource-overlap", "app/models")
      ]
    )
    expect(boundary_markers).to eq(
      [
        marker("resource-path", "app"),
        marker("resource-path", "app/models"),
        marker("resource-overlap", "app/models")
      ]
    )
  end

  it "uses length-prefixed path bytes for deterministic, ambiguity-free marker digests" do
    first = builder.resource_boundary_markers(
      repository_id:,
      resource_kind: "file",
      resource_path: "a/bc"
    )
    second = builder.resource_boundary_markers(
      repository_id:,
      resource_kind: "file",
      resource_path: "ab/c"
    )

    expect(first).not_to eq(second)
    expect(first).to all(match(/\Acompound:resource-boundary:v1:sha256:[0-9a-f]{64}\z/))
  end

  def marker(prefix, path)
    path_digest = OpenSSL::Digest::SHA256.hexdigest("#{path.bytesize}:#{path}")
    Coordinator::Shared::CompoundMarkerBuilder.new.call(
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "resource-boundary",
        components: [
          "repository:#{repository_id}",
          "boundary-role:#{prefix}",
          "resource-path-digest:sha256:#{path_digest}"
        ]
      )
    ).marker
  end
end
