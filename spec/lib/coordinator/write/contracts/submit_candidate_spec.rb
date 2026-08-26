# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::SubmitCandidate do
  subject(:contract) { described_class.new }

  it "accepts one strict manifest-only SHA-1 submission" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h.keys).to contain_exactly(
      :command_id, :actor, :candidate_id, :change_set_id, :work_item_id,
      :attempt_id, :repository_id, :target_branch, :base_commit_oid,
      :head_commit_oid, :checkpoint_kind, :lease_set_id, :leases,
      :change_manifest
    )
  end

  it "accepts every frozen manifest status field contract" do
    files = [
      file(status: "added", old: nil),
      file(status: "modified"),
      file(status: "deleted", new: nil),
      file(status: "renamed", new_path: "lib/renamed.rb"),
      file(status: "copied", new_path: "lib/copied.rb"),
      file(status: "type_changed", old_mode: "100644", new_mode: "120000"),
      file(status: "submodule_changed", old_mode: "160000", new_mode: "160000")
    ]

    expect(contract.call(valid_input(change_manifest: manifest(files:)))).to be_success
  end

  it "rejects mismatched formats, unchanged heads, malformed branches, and malformed status fields" do
    cases = [
      valid_input(head_commit_oid: "a" * 40),
      valid_input(head_commit_oid: "b" * 64),
      valid_input(target_branch: "refs/../bad"),
      valid_input(change_manifest: manifest(files: [ file(status: "added") ]))
    ]

    cases.each { expect(contract.call(_1)).to be_failure }
  end

  it "rejects duplicate lease resources and out-of-format evidence OIDs" do
    duplicate = valid_input
    duplicate[:leases] = [ duplicate[:leases].first, duplicate[:leases].first.merge(lease_id: uuid("2")) ]
    foreign_oid = valid_input(
      build_context: {
        collector_version: "build-context-v1",
        inputs: [ { kind: "runtime_version", path: ".ruby-version", blob_oid: "f" * 64 } ],
        environment: []
      }
    )

    expect(contract.call(duplicate)).to be_failure
    expect(contract.call(foreign_oid)).to be_failure
  end

  it "keeps Candidate manifests within the 32-resource write-set boundary" do
    maximum = Coordinator::Shared::Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT
    files = Array.new(maximum + 1) do |index|
      file(old_path: "lib/example_#{index}.rb")
    end

    result = contract.call(valid_input(change_manifest: manifest(files:)))

    expect(result).to be_failure
    expect(result.errors.to_h.dig(:change_manifest, :files).join).to include(
      "split larger work into separate WorkItems"
    )
  end

  def valid_input(**overrides)
    {
      command_id: "cmd-candidate-1",
      actor: { kind: "agent", id: "agent-7" },
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-18",
      repository_id: "billing",
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      lease_set_id: uuid("1"),
      leases: [
        {
          resource_key_hash: "sha256:#{"1" * 64}",
          lease_id: uuid("2"),
          fencing_token: 1
        }
      ],
      change_manifest: manifest
    }.merge(overrides)
  end

  def manifest(files: [ file ])
    { collector_version: "git-evidence-v1", files: }
  end

  def file(
    status: "modified",
    old: true,
    new: true,
    old_path: "lib/example.rb",
    new_path: old_path,
    old_mode: "100644",
    new_mode: old_mode
  )
    {
      status:,
      old_path: old ? old_path : nil,
      new_path: new ? new_path : nil,
      old_blob_oid: old ? "c" * 40 : nil,
      new_blob_oid: new ? "d" * 40 : nil,
      old_mode: old ? old_mode : nil,
      new_mode: new ? new_mode : nil
    }
  end

  def uuid(suffix)
    "01919191-9191-7191-8191-91919191919#{suffix}"
  end
end
