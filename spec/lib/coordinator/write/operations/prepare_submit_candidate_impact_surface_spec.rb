# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareSubmitCandidateImpactSurface do
  subject(:preparer) { described_class.new }

  it "IMP-01-DIGEST-01 canonicalizes directional set order into one strict command" do
    first = preparer.call(input(%w[runtime:ruby dependency:rubygems:rails])).value!
    second = preparer.call(input(%w[dependency:rubygems:rails runtime:ruby])).value!

    expect(first.surface.produces.map(&:impact_key)).to eq(
      %w[dependency:rubygems:rails runtime:ruby]
    )
    expect(first.surface.digest).to eq(second.surface.digest)
    expect(first.surface.analyzer).to have_attributes(
      kind: "agent", id: "analyzer-7", analyzer_version: "impact-v1"
    )
  end

  it "returns a typed invalid-input failure" do
    result = preparer.call(input([]))

    expect(result).to be_failure
    expect(result.failure).to have_attributes(code: :invalid_input)
  end

  def input(keys)
    {
      command_id: "cmd-impact-1",
      actor: { kind: "agent", id: "analyzer-7" },
      candidate_id: "CAN-41",
      repository_id: "billing",
      head_commit_oid: "b" * 40,
      manifest_digest: "sha256:#{"a" * 64}",
      analyzer_version: "impact-v1",
      surface: {
        produces: keys.map { { impact_key: _1, after: "present" } },
        consumes: [],
        may_affect: [],
        assumes: []
      }
    }
  end
end
