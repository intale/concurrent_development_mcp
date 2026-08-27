# frozen_string_literal: true

RSpec.describe Coordinator::Write::FileResourceNormalizer do
  subject(:normalizer) { described_class.new }

  it "preserves an exact Git path while distinguishing file and directory identities" do
    file = normalizer.call(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      scope: RepositoryScenario::DEFAULT_SCOPE,
      kind: "file",
      path: "app/models/User.rb",
      base_blob_oid: "b" * 40
    ).value!
    directory = normalizer.call(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      scope: RepositoryScenario::DEFAULT_SCOPE,
      kind: "directory",
      path: "app/models",
      base_blob_oid: nil
    ).value!

    expect(file.to_h).to include(
      kind: "file",
      path: "app/models/User.rb",
      resource_key: "scope:project:test/billing:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:file:app/models/User.rb",
      policy_version: "coordinator-resource-key/v3"
    )
    expect(directory.to_h).to include(
      kind: "directory",
      path: "app/models",
      resource_key: "scope:project:test/billing:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:directory:app/models",
      policy_version: "coordinator-resource-key/v3"
    )
    expect(file.resource_key_hash).not_to eq(directory.resource_key_hash)
  end

  it "keeps byte-distinct case and Unicode sequences distinct" do
    composed = normalizer.call(repository_id: "billing", kind: "file", path: "Models/Å.rb", base_blob_oid: nil).value!
    decomposed = normalizer.call(repository_id: "billing", kind: "file", path: "Models/A\u030A.rb", base_blob_oid: nil).value!
    lower = normalizer.call(repository_id: "billing", kind: "file", path: "models/å.rb", base_blob_oid: nil).value!

    expect(composed.path).to eq("Models/Å.rb")
    expect([ composed.resource_key_hash, decomposed.resource_key_hash, lower.resource_key_hash ].uniq.length).to eq(3)
  end

  it "rejects aliasing syntax instead of rewriting caller bytes" do
    cases = {
      "app\\models\\user.rb" => :resource_path_backslash,
      "app//models/user.rb" => :resource_path_empty_component,
      "app/./models/user.rb" => :resource_path_dot_component,
      "app/models/../user.rb" => :resource_path_parent_component,
      "app/models/" => :resource_path_trailing_separator,
      "/etc/passwd" => :resource_path_absolute,
      "C:/repo/file.rb" => :resource_path_absolute,
      "app/\u0000bad" => :resource_path_control_character,
      "." => :resource_path_dot_component
    }

    cases.each do |path, code|
      result = normalizer.call(repository_id: "billing", kind: "file", path:, base_blob_oid: nil)
      expect(result.failure.code).to eq(code)
    end
  end

  it "bounds UTF-8 bytes and path depth explicitly" do
    too_long = "é" * 513
    too_deep = 33.times.map { "a" }.join("/")
    invalid_utf8 = "\xFF".b.force_encoding(Encoding::UTF_8)

    expect(normalizer.call(repository_id: "billing", kind: "file", path: too_long, base_blob_oid: nil).failure.code)
      .to eq(:resource_path_too_long)
    expect(normalizer.call(repository_id: "billing", kind: "file", path: too_deep, base_blob_oid: nil).failure.code)
      .to eq(:resource_path_too_deep)
    expect(normalizer.call(repository_id: "billing", kind: "file", path: invalid_utf8, base_blob_oid: nil).failure.code)
      .to eq(:resource_path_encoding)
  end

  it "rejects resource kinds outside the Git file/directory model" do
    result = normalizer.call(
      repository_id: "billing",
      kind: "contract",
      path: "payments/v1",
      base_blob_oid: nil
    )

    expect(result.failure.code).to eq(:unsupported_resource_kind)
  end
end
