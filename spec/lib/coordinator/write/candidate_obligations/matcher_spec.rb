# frozen_string_literal: true

RSpec.describe Coordinator::Write::CandidateObligations::Matcher do
  subject(:matcher) { described_class.new }

  it "derives all exact directional path and semantic reasons in stable order" do
    source = CandidateObligationExamples.evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "Gemfile.lock",
      produces: [ "dependency:rubygems:rails" ]
    )
    target = CandidateObligationExamples.evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "Gemfile.lock",
      observed_paths: [ "Gemfile.lock" ],
      assumes: [ "dependency:rubygems:rails" ]
    )

    reasons = matcher.call(source:, target:)

    expect(reasons.map(&:kind)).to eq(%w[
      changed_resource_overlap
      observed_input_changed
      semantic_key_match
    ])
    expect(reasons.map(&:matches)).to eq([
      [ "Gemfile.lock" ],
      [ "Gemfile.lock" ],
      [ "dependency:rubygems:rails" ]
    ])
    expect(reasons.map(&:source_evidence)).to eq([
      source.subject.manifest_event,
      source.subject.manifest_event,
      source.subject.surface_event
    ])
    expect(reasons.map(&:target_evidence)).to eq([
      target.subject.manifest_event,
      target.subject.build_context_event,
      target.subject.surface_event
    ])
  end

  it "keeps path matching repository-local and semantic matching cross-repository" do
    source = CandidateObligationExamples.evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "schema.graphql",
      produces: [ "contract:graphql:billing" ],
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
    )
    target = CandidateObligationExamples.evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "schema.graphql",
      observed_paths: [ "schema.graphql" ],
      consumes: [ "contract:graphql:billing" ],
      repository_id: RepositoryScenario.repository_id("orders")
    )

    reasons = matcher.call(source:, target:)

    expect(reasons.map(&:kind)).to eq([ "semantic_key_match" ])
  end

  it "returns no reason for an exact directional miss" do
    source = CandidateObligationExamples.evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "lib/source.rb",
      produces: [ "contract:source:v1" ]
    )
    target = CandidateObligationExamples.evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "lib/target.rb",
      observed_paths: [ "config/target.yml" ],
      consumes: [ "contract:target:v1" ]
    )

    expect(matcher.call(source:, target:)).to be_empty
  end
end
