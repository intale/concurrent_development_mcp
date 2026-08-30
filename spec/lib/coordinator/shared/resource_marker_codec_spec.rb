# frozen_string_literal: true

RSpec.describe Coordinator::Shared::ResourceMarkerCodec do
  subject(:codec) { described_class.new }

  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }

  it "encodes exact UTF-8 byte lengths without hashing natural-key components" do
    path = "app/Å.rb"

    expect(codec.identity(repository_id:, kind: "file", normalized_path: path)).to eq(
      "resource-identity:v1|r=36:#{repository_id}|k=4:file|p=9:app/Å.rb"
    )
    expect(codec.current_path(repository_id:, normalized_path: path)).to eq(
      "resource-current-path:v1|r=36:#{repository_id}|p=9:app/Å.rb"
    )
    expect(codec.boundary(repository_id:, role: "resource-path", normalized_path: path)).to eq(
      "resource-boundary:v2|r=36:#{repository_id}|role=13:resource-path|p=9:app/Å.rb"
    )
  end

  it "keeps identity kind-specific while sharing one current-path boundary" do
    path = "docs|p=4:file"

    file = codec.identity(repository_id:, kind: "file", normalized_path: path)
    directory = codec.identity(repository_id:, kind: "directory", normalized_path: path)

    expect(file).not_to eq(directory)
    expect(codec.current_path(repository_id:, normalized_path: path)).to end_with(
      "|p=13:docs|p=4:file"
    )
  end
end
