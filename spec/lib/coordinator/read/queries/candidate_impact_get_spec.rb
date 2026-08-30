# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateImpactGet, :read_model do
  subject(:query) { described_class.new }

  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000071" }

  it "serves available partial evidence without a freshness gate" do
    candidate_id = "CAN-impact-query-lag"
    absent = query.call(candidate_id:, direction: "outgoing").value!
    create(
      :coordinator_read_candidate,
      candidate_id:,
      build_context_digest: "sha256:#{'b' * 64}"
    )
    partial = query.call(candidate_id:, direction: "outgoing").value!

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
    source, target = create_matching_candidates(change_set_id: "CS-impact-match")

    outgoing = query.call(candidate_id: source.candidate_id, direction: "outgoing").value!.data.page
    incoming = query.call(candidate_id: target.candidate_id, direction: "incoming").value!.data.page

    relationship = outgoing.relationships.sole
    expect(relationship).to have_attributes(
      relationship_kind: "potentially_affects",
      counterpart: have_attributes(candidate_id: target.candidate_id)
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
    expect(incoming.relationships.sole.counterpart.candidate_id).to eq(source.candidate_id)
    expect(outgoing.impact_surface).to have_attributes(
      evidence_status: "attributed_unverified",
      analyzer: have_attributes(id: "analyzer-7")
    )
  end

  it "pages distinct counterparts by submission global position and rejects invalid input" do
    change_set_id = "CS-impact-page"
    subject_candidate = create_candidate(
      candidate_id: "CAN-impact-page-source",
      change_set_id:,
      submitted_global_position: 100
    )
    first = create_candidate(
      candidate_id: "CAN-impact-page-target-1",
      change_set_id:,
      submitted_global_position: 101
    )
    second = create_candidate(
      candidate_id: "CAN-impact-page-target-2",
      change_set_id:,
      submitted_global_position: 102
    )
    [ subject_candidate, first, second ].each { create_changed_resource(_1) }

    first_page = query.call(
      candidate_id: subject_candidate.candidate_id,
      direction: "outgoing",
      limit: 1
    ).value!.data.page
    second_page = query.call(
      candidate_id: subject_candidate.candidate_id,
      direction: "outgoing",
      after_global_position: first_page.next_global_position,
      limit: 1
    ).value!.data.page
    invalid = query.call(candidate_id: "bad id", direction: "sideways", limit: 101).value!

    expect(first_page).to have_attributes(has_more: true)
    expect(first_page.relationships.sole.counterpart.candidate_id).to eq(first.candidate_id)
    expect(second_page).to have_attributes(has_more: false, next_global_position: nil)
    expect(second_page.relationships.sole.counterpart.candidate_id).to eq(second.candidate_id)
    expect(invalid).to have_attributes(status: "invalid")
  end

  it "adds coherent advisory and gating policy signals from the latest available rows" do
    advisory_candidate = create_candidate(
      candidate_id: "CAN-impact-policy-advisory",
      change_set_id: "CS-impact-policy-advisory",
      submitted_global_position: 110
    )
    create_policy(change_set_id: advisory_candidate.change_set_id, enforcement: "advisory")

    advisory = query.call(
      candidate_id: advisory_candidate.candidate_id,
      direction: "outgoing"
    ).value!
    expect(advisory.data.page.impact_policy).to have_attributes(
      change_set_id: advisory_candidate.change_set_id,
      required_evidence: [ "combined_tests" ],
      enforcement: "advisory"
    )
    expect(advisory.warnings).to include(
      "The latest available Candidate-impact policy is advisory; consider external verification."
    )
    expect(advisory.next_actions).to be_empty

    gating_candidate = create_candidate(
      candidate_id: "CAN-impact-policy-gating",
      change_set_id: "CS-impact-policy-gating",
      submitted_global_position: 111
    )
    create_policy(change_set_id: gating_candidate.change_set_id, enforcement: "merge_gate")

    gating = query.call(candidate_id: gating_candidate.candidate_id, direction: "outgoing").value!
    expect(gating.data.page.impact_policy).to have_attributes(enforcement: "merge_gate")
    expect(gating.warnings).to include(
      "The latest available Candidate-impact policy is gating; the obligation projection may lag."
    )
    expect(gating.next_actions.map(&:to_h)).to eq([
      {
        tool: "verification_obligations_list",
        arguments: { change_set_id: gating_candidate.change_set_id }
      }
    ])
  end

  def create_matching_candidates(change_set_id:)
    source = create_candidate(
      candidate_id: "CAN-impact-match-source",
      change_set_id:,
      submitted_global_position: 100
    )
    target_surface = impact_surface(target: true, build_context_digest: "sha256:#{'e' * 64}")
    target = create_candidate(
      candidate_id: "CAN-impact-match-target",
      change_set_id:,
      submitted_global_position: 101,
      build_context: true,
      impact_surface: target_surface
    )
    [ source, target ].each { create_changed_resource(_1) }
    create(
      :coordinator_read_candidate_observed_input,
      candidate_id: target.candidate_id,
      change_set_id:,
      repository_id:,
      path: "lib/candidate.rb"
    )
    create(
      :coordinator_read_candidate_impact_key,
      candidate_id: source.candidate_id,
      change_set_id:,
      direction: "produces",
      impact_key: "contract:payments-api:v2"
    )
    create(
      :coordinator_read_candidate_impact_key,
      candidate_id: target.candidate_id,
      change_set_id:,
      direction: "consumes",
      impact_key: "contract:payments-api:v2"
    )
    [ source, target ]
  end

  def create_candidate(
    candidate_id:,
    change_set_id:,
    submitted_global_position:,
    build_context: false,
    impact_surface: nil
  )
    traits = [ :manifest_observed, :impact_surface_observed ]
    traits << :build_context_observed if build_context
    create(
      :coordinator_read_candidate,
      *traits,
      candidate_id:,
      change_set_id:,
      repository_id:,
      submitted_global_position:,
      head_commit_oid: format("%040x", submitted_global_position),
      impact_surface: impact_surface || self.impact_surface(target: false, build_context_digest: nil)
    )
  end

  def create_changed_resource(candidate)
    create(
      :coordinator_read_candidate_changed_resource,
      candidate_id: candidate.candidate_id,
      change_set_id: candidate.change_set_id,
      repository_id: candidate.repository_id,
      path: "lib/candidate.rb"
    )
  end

  def impact_surface(target:, build_context_digest:)
    {
      "policy_version" => "candidate-impact-surface/v1",
      "surface_digest" => "sha256:#{target ? '8' * 64 : '9' * 64}",
      "evidence_revision" => 1,
      "manifest_digest" => "sha256:#{'d' * 64}",
      "build_context_digest" => build_context_digest,
      "produces" => target ? [] : [
        { "impact_key" => "contract:payments-api:v2", "before" => nil, "after" => "available" }
      ],
      "consumes" => target ? [
        { "impact_key" => "contract:payments-api:v2", "value" => "required" }
      ] : [],
      "may_affect" => [],
      "assumes" => [],
      "analyzer" => { "kind" => "agent", "id" => "analyzer-7", "analyzer_version" => "factory-v1" },
      "evidence_status" => "attributed_unverified"
    }
  end

  def create_policy(change_set_id:, enforcement:)
    decision = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-#{change_set_id}",
      topic_id: "candidate.impact_policy",
      change_set_id:,
      enforcement_level: enforcement
    )
    partition_id = "changeset:#{change_set_id}:candidate"
    head = {
      "decision_id" => decision.decision_id,
      "decision_revision" => 1,
      "event" => decision.activated_event
    }
    create(
      :coordinator_read_decision_partition_head,
      partition_id:,
      decision_id: decision.decision_id,
      partition: {
        "partition_id" => partition_id,
        "topic_root" => "candidate",
        "anchor_kind" => "changeset",
        "anchor_id" => change_set_id
      },
      decision: head,
      active_decisions: [ head ]
    )
  end
end
