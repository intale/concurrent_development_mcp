# frozen_string_literal: true

RSpec.describe Coordinator::Write::ResourceIdentityNormalizer do
  subject(:normalizer) { described_class.new }

  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }

  it "creates one immutable canonical identity and both plain marker boundaries" do
    identity = normalizer.call(
      repository_id:,
      kind: "file",
      path: "app/models/User.rb"
    ).value!

    expect(identity.to_h).to eq(
      repository_id:,
      kind: "file",
      normalized_path: "app/models/User.rb",
      identity_marker: "resource-identity:v1|r=36:#{repository_id}|k=4:file|p=18:app/models/User.rb",
      current_path_marker: "resource-current-path:v1|r=36:#{repository_id}|p=18:app/models/User.rb"
    )
    expect(identity).to be_frozen
  end

  it "preserves byte-distinct case and Unicode sequences" do
    paths = [ "Models/Å.rb", "Models/A\u030A.rb", "models/å.rb" ]
    markers = paths.map do |path|
      normalizer.call(repository_id:, kind: "file", path:).value!.identity_marker
    end

    expect(markers.uniq.length).to eq(3)
  end

  it "reports invalid Repository, kind, aliasing syntax, encoding, byte size, and depth through Dry validation" do
    cases = [
      { repository_id: "not-a-uuid", kind: "file", path: "a.rb" },
      { repository_id:, kind: "contract", path: "a.rb" },
      { repository_id:, kind: "file", path: "app/../a.rb" },
      { repository_id:, kind: "file", path: "\xFF".b.force_encoding(Encoding::UTF_8) },
      { repository_id:, kind: "file", path: "é" * 513 },
      { repository_id:, kind: "file", path: Array.new(33, "a").join("/") }
    ]

    cases.each do |input|
      failure = normalizer.call(**input).failure

      expect(failure.code).to eq(:resource_identity_invalid)
      expect(failure.details.fetch(:errors)).not_to be_empty
    end
  end

  it "generates Resource IDs as server-owned UUIDv7 values with no identity payload input" do
    generator = Coordinator::Write::ResourceIdGenerator.new
    ids = Array.new(10) { generator.call }

    expect(ids).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(ids.uniq.length).to eq(10)
  end
end
