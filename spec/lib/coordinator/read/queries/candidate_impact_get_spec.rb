# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateImpactGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::CandidatesV1.new }

  it "serves available partial evidence without a freshness gate" do
    scenario = CandidateScenario.submit(prefix: "impact-query-lag")
    events = scenario.fetch(:events)

    absent = query.call(candidate_id: "CAN-impact-query-lag", direction: "outgoing").value!
    projector.call(events.first)
    partial = query.call(candidate_id: "CAN-impact-query-lag", direction: "outgoing").value!

    expect(absent).to have_attributes(status: "not_found")
    expect(partial).to have_attributes(status: "ok")
    expect(partial.data.page).to have_attributes(
      impact_surface: nil,
      relationships: [],
      has_more: false
    )
    expect(partial.warnings).to contain_exactly(
      "The Candidate manifest has not yet been observed by this projection.",
      "The Candidate build context has not yet been observed by this projection.",
      "The Candidate impact surface has not yet been observed by this projection."
    )
  end

  it "aggregates directional path, observed-input, and semantic matches with exact evidence" do
    subject_scenario, target_scenario = matching_candidates
    project_candidate(subject_scenario)
    project_candidate(target_scenario)

    outgoing = query.call(
      candidate_id: subject_scenario.dig(:input, :candidate_id),
      direction: "outgoing"
    ).value!.data.page
    incoming = query.call(
      candidate_id: target_scenario.dig(:input, :candidate_id),
      direction: "incoming"
    ).value!.data.page

    relationship = outgoing.relationships.sole
    expect(relationship).to have_attributes(
      relationship_kind: "potentially_affects",
      counterpart: have_attributes(candidate_id: target_scenario.dig(:input, :candidate_id))
    )
    expect(relationship.reasons.map(&:kind)).to eq(%w[
      changed_resource_overlap
      observed_input_changed
      semantic_key_match
    ])
    expect(relationship.reasons.map(&:matches)).to eq([
      [ "lib/candidate.rb" ],
      [ "lib/candidate.rb" ],
      [ "contract:payments-api:v2" ]
    ])
    expect(relationship.reasons.flat_map do |reason|
      [ reason.source_evidence.event.type, reason.target_evidence.event.type ]
    end).to eq(%w[
      CandidateChangeManifestCaptured CandidateChangeManifestCaptured
      CandidateChangeManifestCaptured CandidateBuildContextCaptured
      CandidateImpactSurfaceDerived CandidateImpactSurfaceDerived
    ])
    expect(incoming.relationships.sole.counterpart.candidate_id).to eq(
      subject_scenario.dig(:input, :candidate_id)
    )
    expect(outgoing.impact_surface).to have_attributes(
      evidence_status: "attributed_unverified",
      analyzer: have_attributes(id: "analyzer-7")
    )
  end

  it "pages distinct counterparts by submission global position and rejects invalid input" do
    subject_scenario, first_target = matching_candidates(prefix: "impact-query-page")
    prepared = subject_scenario.fetch(:prepared)
    second_target = submit_candidate_from(
      prepared,
      candidate_id: "CAN-impact-query-page-target-2",
      command_id: "cmd-impact-query-page-target-2",
      head_commit_oid: "f" * 40,
      build_context: true
    )
    [ subject_scenario, first_target, second_target ].each { project_candidate(_1) }

    first = query.call(
      candidate_id: subject_scenario.dig(:input, :candidate_id),
      direction: "outgoing",
      limit: 1
    ).value!.data.page
    second = query.call(
      candidate_id: subject_scenario.dig(:input, :candidate_id),
      direction: "outgoing",
      after_global_position: first.next_global_position,
      limit: 1
    ).value!.data.page
    invalid = query.call(
      candidate_id: "bad id",
      direction: "sideways",
      limit: 101
    ).value!

    expect(first).to have_attributes(has_more: true)
    expect(first.relationships.length).to eq(1)
    expect(first.next_global_position).to eq(
      first.relationships.sole.counterpart.submitted.global_position
    )
    expect(second).to have_attributes(has_more: false, next_global_position: nil)
    expect(second.relationships.length).to eq(1)
    expect(invalid).to have_attributes(status: "invalid")
  end

  def matching_candidates(prefix: "impact-query-match")
    prepared = CandidateScenario.prepare(prefix:, path: "lib/candidate.rb")
    source = submit_candidate_from(
      prepared,
      candidate_id: "CAN-#{prefix}-source",
      command_id: "cmd-#{prefix}-source",
      head_commit_oid: "b" * 40,
      build_context: false
    )
    target = submit_candidate_from(
      prepared,
      candidate_id: "CAN-#{prefix}-target",
      command_id: "cmd-#{prefix}-target",
      head_commit_oid: "e" * 40,
      build_context: true
    )
    CandidateScenario.submit_impact(source, surface: source_surface)
    CandidateScenario.submit_impact(target, surface: target_surface)
    [ source.merge(prepared:), target.merge(prepared:) ]
  end

  def submit_candidate_from(prepared, candidate_id:, command_id:, head_commit_oid:, build_context:)
    input = prepared.fetch(:input).merge(candidate_id:, command_id:, head_commit_oid:)
    input = input.merge(build_context: CandidateScenario.build_context_for("lib/candidate.rb")) if build_context
    completion = CandidateScenario.execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    {
      input:,
      completion:,
      events: CandidateScenario.candidate_events(candidate_id)
    }
  end

  def project_candidate(scenario)
    CandidateScenario.candidate_events(scenario.dig(:input, :candidate_id)).each { projector.call(_1) }
  end

  def source_surface
    {
      produces: [ { impact_key: "contract:payments-api:v2", after: "available" } ],
      consumes: [],
      may_affect: [],
      assumes: []
    }
  end

  def target_surface
    {
      produces: [],
      consumes: [ { impact_key: "contract:payments-api:v2", value: "required" } ],
      may_affect: [],
      assumes: []
    }
  end
end
