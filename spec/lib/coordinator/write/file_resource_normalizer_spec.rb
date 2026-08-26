# frozen_string_literal: true

RSpec.describe Coordinator::Write::FileResourceNormalizer do
  subject(:normalizer) { described_class.new }

  it "normalizes lexical Git paths into a versioned canonical identity" do
    result = normalizer.call(
      repository_id: "billing",
      kind: "file",
      path: ".\\app//services/../models/User.rb",
      base_blob_oid: "b" * 40
    )

    expect(result).to be_success
    expect(result.value!.to_h).to eq(
      kind: "file",
      path: "app/models/User.rb",
      base_blob_oid: "b" * 40,
      resource_key: "repo:billing:file:app/models/User.rb",
      resource_key_hash: "sha256:71b26d2dd05c487749a92ba97a20c3144710d2e5f0750aded67d8f1d0f6b8e51",
      policy_version: "coordinator-resource-key/v1"
    )
  end

  it "binds an authoritative identity to exact scope and repository UUID" do
    result = normalizer.call(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      scope: RepositoryScenario::DEFAULT_SCOPE,
      kind: "file",
      path: "./app/models/user.rb",
      base_blob_oid: nil
    )

    expect(result.value!).to have_attributes(
      resource_key: "scope:project:test/billing:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:file:app/models/user.rb",
      policy_version: "coordinator-resource-key/v2"
    )
    expect(result.value!.resource_key_hash).to match(/\Asha256:[0-9a-f]{64}\z/)
  end

  it "preserves case and Unicode code-point sequences" do
    upper = normalizer.call(repository_id: "billing", kind: "file", path: "Models/Å.rb", base_blob_oid: nil).value!
    lower = normalizer.call(repository_id: "billing", kind: "file", path: "models/å.rb", base_blob_oid: nil).value!

    expect(upper.resource_key_hash).not_to eq(lower.resource_key_hash)
    expect(upper.path).to eq("Models/Å.rb")
  end

  it "returns explicit errors for unsafe or unsupported resource identities" do
    cases = {
      "../secrets" => :resource_path_escape,
      "/etc/passwd" => :resource_path_absolute,
      "C:\\repo\\file.rb" => :resource_path_absolute,
      "app/\u0000bad" => :resource_path_control_character,
      "." => :resource_path_empty
    }

    cases.each do |path, code|
      result = normalizer.call(repository_id: "billing", kind: "file", path:, base_blob_oid: nil)
      expect(result.failure.code).to eq(code)
    end

    unsupported = normalizer.call(
      repository_id: "billing",
      kind: "contract",
      path: "payments/v1",
      base_blob_oid: nil
    )
    expect(unsupported.failure.code).to eq(:unsupported_resource_kind)
  end
end
