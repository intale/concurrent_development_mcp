# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareSubmitCandidate do
  subject(:prepare) { described_class.new }

  it "builds immutable normalized manifest and build-context evidence" do
    result = prepare.call(input_with_context)

    expect(result).to be_success
    command = result.value!
    expect(command).to have_attributes(
      object_format: "sha1",
      target_branch: "agents/payments",
      checkpoint_kind: "handoff"
    )
    expect(command.manifest).to have_attributes(
      policy_version: "candidate-change-manifest/v1",
      digest: match(/\Asha256:[0-9a-f]{64}\z/),
      collector: have_attributes(kind: "agent", id: "agent-7", collector_version: "git-evidence-v1")
    )
    expect(command.manifest.files.first).to have_attributes(
      old_path: "lib/payments.rb",
      new_path: "lib/payments.rb"
    )
    expect(command.actual_resources).to contain_exactly(
      have_attributes(path: "lib/payments.rb", base_blob_oid: "c" * 40),
      have_attributes(path: "spec/payments_spec.rb", base_blob_oid: nil)
    )
    expect(command.build_context).to have_attributes(
      policy_version: "candidate-build-context/v1",
      digest: match(/\Asha256:[0-9a-f]{64}\z/),
      inputs: [ have_attributes(path: ".ruby-version", kind: "runtime_version") ],
      environment: [ have_attributes(name: "rails", value: "8.0"), have_attributes(name: "ruby", value: "4.0.6") ]
    )
  end

  it "normalizes equivalent order and aliases to stable evidence digests" do
    original = prepare.call(input_with_context).value!
    reordered = input_with_context
    reordered[:change_manifest][:files] = reordered[:change_manifest][:files].reverse
    reordered[:build_context][:environment] = reordered[:build_context][:environment].reverse
    reordered[:build_context][:inputs].first[:path] = "./config/../.ruby-version"
    changed = prepare.call(reordered).value!

    expect(changed.manifest.digest).to eq(original.manifest.digest)
    expect(changed.build_context.digest).to eq(original.build_context.digest)
  end

  it "expands rename old and new resources and rejects more than 32 actual resources" do
    renamed = valid_input
    renamed[:change_manifest][:files] = [
      file(status: "renamed", old_path: "lib/old.rb", new_path: "lib/new.rb")
    ]
    command = prepare.call(renamed).value!

    expect(command.actual_resources.map(&:path)).to eq(%w[lib/new.rb lib/old.rb])
    expect(command.actual_resources.find { _1.path == "lib/old.rb" }.base_blob_oid).to eq("c" * 40)
    expect(command.actual_resources.find { _1.path == "lib/new.rb" }.base_blob_oid).to be_nil

    oversized = valid_input
    oversized[:change_manifest][:files] = 33.times.map do |index|
      file(status: "added", old: false, new_path: "generated/#{index}.rb")
    end
    result = prepare.call(oversized)

    expect(result.failure).to have_attributes(code: :invalid_candidate_evidence)
  end

  it "rejects normalized duplicate entries and conflicting base evidence" do
    duplicate = valid_input
    duplicate[:change_manifest][:files] = [ file, file(old_path: "./lib/example.rb", new_path: "lib/./example.rb") ]

    result = prepare.call(duplicate)

    expect(result.failure).to have_attributes(code: :invalid_candidate_evidence)
  end

  def input_with_context
    valid_input(
      target_branch: "agents/payments",
      checkpoint_kind: "handoff",
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          file(old_path: "lib/./services/../payments.rb", new_path: "lib/./services/../payments.rb"),
          file(status: "added", old: false, new_path: "spec/payments_spec.rb")
        ]
      },
      build_context: {
        collector_version: "build-context-v1",
        inputs: [ { kind: "runtime_version", path: ".ruby-version", blob_oid: "e" * 40 } ],
        environment: [ { name: "ruby", value: "4.0.6" }, { name: "rails", value: "8.0" } ],
        dependency_graph_digest: "sha256:#{"a" * 64}",
        test_environment_digest: nil
      }
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
      lease_set_id: "01919191-9191-7191-8191-919191919191",
      leases: [
        {
          resource_key_hash: "sha256:#{"1" * 64}",
          lease_id: "01919191-9191-7191-8191-919191919192",
          fencing_token: 1
        }
      ],
      change_manifest: { collector_version: "git-evidence-v1", files: [ file ] }
    }.merge(overrides)
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
end
