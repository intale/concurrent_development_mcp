# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::SubmitCandidateImpactSurface do
  subject(:contract) { described_class.new }

  it "IMP-01-SURFACE-01 accepts all four strict directional shapes" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h.fetch(:surface).keys).to contain_exactly(
      :produces, :consumes, :may_affect, :assumes
    )
  end

  it "IMP-01-INPUT-01 rejects empty, duplicate, malformed, oversized, and unknown input" do
    cases = [
      valid_input(surface: empty_surface),
      valid_input(
        surface: valid_surface.merge(
          may_affect: [ { impact_key: "runtime:ruby" }, { impact_key: "runtime:ruby" } ]
        )
      ),
      valid_input(surface: valid_surface.merge(may_affect: [ { impact_key: "Runtime Ruby" } ])),
      valid_input(analyzer_version: "a" * 101),
      valid_input(unexpected: true)
    ]

    cases.each { expect(contract.call(_1)).to be_failure }
  end

  it "rejects malformed identities, OIDs, digests, and impact values" do
    cases = [
      valid_input(candidate_id: "bad id"),
      valid_input(repository_id: "BadRepo"),
      valid_input(head_commit_oid: "B" * 40),
      valid_input(manifest_digest: "sha256:no"),
      valid_input(
        surface: valid_surface.merge(
          assumes: [ { impact_key: "runtime:ruby", predicate: "" } ]
        )
      )
    ]

    cases.each { expect(contract.call(_1)).to be_failure }
  end

  def valid_input(**overrides)
    {
      command_id: "cmd-impact-1",
      actor: { kind: "agent", id: "analyzer-7" },
      candidate_id: "CAN-41",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      head_commit_oid: "b" * 40,
      manifest_digest: "sha256:#{"a" * 64}",
      build_context_digest: "sha256:#{"b" * 64}",
      analyzer_version: "impact-analyzer-v1",
      surface: valid_surface
    }.merge(overrides)
  end

  def valid_surface
    {
      produces: [
        {
          impact_key: "dependency:rubygems:rails",
          before: "4.2.11",
          after: "5.0.0"
        }
      ],
      consumes: [ { impact_key: "contract:payments-api:v2", value: "v2" } ],
      may_affect: [ { impact_key: "framework:rails:controller-lifecycle" } ],
      assumes: [ { impact_key: "runtime:ruby", predicate: ">= 3.3" } ]
    }
  end

  def empty_surface
    { produces: [], consumes: [], may_affect: [], assumes: [] }
  end
end
