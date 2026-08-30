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
    expect(markers).to all(start_with("resource-boundary:v2|r=36:#{repository_id}|"))
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

  it "uses plain length-prefixed components without digesting repository paths" do
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
    expect(first).to all(start_with("resource-boundary:v2|r=36:#{repository_id}|"))
    expect(first).to all(include("|p="))
    expect(first.join).not_to include("sha256")
  end

  def marker(prefix, path)
    Coordinator::Shared::ResourceMarkerCodec.new.boundary(
      repository_id:,
      role: prefix,
      normalized_path: path
    )
  end
end
