# frozen_string_literal: true

RSpec.describe Coordinator::Write::Candidates::ImpactIndexMarkerBuilder do
  subject(:builder) { described_class.new }

  it "derives the exact readable version-2 compound bucket markers" do
    markers = builder.call(evidence:, surface:)
    definitions = markers.map do |marker|
      Coordinator::Shared::Markers::CodecV2.new.decode(marker).value!.definition
    end
    component_maps = definitions.map do |definition|
      definition.components.to_h { [ _1.dimension, _1.value ] }
    end

    expect(markers).to eq(markers.uniq.sort_by(&:b))
    expect(markers).to all(start_with("compound:candidate-impact-index:v2|"))
    expect(component_maps).to contain_exactly(
      marker_components(role: "source", kind: "path", value: "Gemfile", repository: true),
      marker_components(role: "target", kind: "path", value: "Gemfile", repository: true),
      marker_components(
        role: "target",
        kind: "path",
        value: "config/database.yml",
        repository: true
      ),
      marker_components(role: "source", kind: "semantic", value: "dependency:rubygems:rails"),
      marker_components(role: "target", kind: "semantic", value: "schema:orders")
    )
  end

  it "derives reciprocal counterpart roles from the same exact evidence" do
    registered = builder.call(evidence:, surface:)
    outgoing = builder.counterpart(evidence:, surface:, direction: "outgoing")
    incoming = builder.counterpart(evidence:, surface:, direction: "incoming")

    expect(outgoing).to eq(outgoing.uniq.sort_by(&:b))
    expect(incoming).to eq(incoming.uniq.sort_by(&:b))
    expect(outgoing.length).to eq(2)
    expect(incoming.length).to eq(3)
    expect(outgoing & registered).to have_attributes(length: 1)
    expect(incoming & registered).to have_attributes(length: 1)
  end

  def evidence
    Coordinator::Write::Candidates::ImpactSurfaceEvidenceV2.new(candidate:)
  end

  def candidate
    Coordinator::Write::Candidates::StateV2.new(
      candidate_id: "CAN-index",
      change_set_id: "CS-index",
      work_item_id: "W-index",
      attempt_id: "A-index",
      agent_id: "agent-index",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      intention_set_id: "01919191-9191-7191-8191-919191919190",
      manifest_digest: "sha256:#{"a" * 64}",
      build_context_digest: "sha256:#{"b" * 64}",
      manifest:,
      manifest_event: reference("CandidateChangeManifestCaptured", 1),
      build_context:,
      build_context_event: reference("CandidateBuildContextCaptured", 2),
      submission_event: reference("CandidateSubmitted", 3),
      surface_id: nil,
      surface_assignment_event: nil,
      latest_revision: 3
    )
  end

  def marker_components(role:, kind:, value:, repository: false)
    components = {
      "index-policy" => "candidate-impact-exact-index/v2",
      "kind" => kind,
      "role" => role,
      "value" => value
    }
    components["repository"] = RepositoryScenario::DEFAULT_REPOSITORY_ID if repository
    components
  end

  def manifest
    Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id: "CAN-index",
      evidence_revision: 1,
      files: [ Coordinator::Write::Candidates::ManifestFileV1.new(
        status: "modified",
        old_path: "Gemfile",
        new_path: "Gemfile",
        old_blob_oid: "c" * 40,
        new_blob_oid: "d" * 40,
        old_mode: "100644",
        new_mode: "100644"
      ) ]
    )
  end

  def build_context
    Coordinator::Write::Events::CandidateBuildContextCapturedV2.new(
      candidate_id: "CAN-index",
      evidence_revision: 1,
      inputs: [ Coordinator::Write::Candidates::BuildInputV1.new(
        kind: "toolchain_config",
        path: "config/database.yml",
        blob_oid: "e" * 40
      ) ],
      environment: []
    )
  end

  def surface
    Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2.new(
      surface_id: "01919191-9191-7191-8191-919191919194",
      candidate_id: "CAN-index",
      evidence_revision: 1,
      produces: [ Coordinator::Write::Candidates::ImpactTransitionV1.new(
        impact_key: "dependency:rubygems:rails",
        before: "4.2.11",
        after: "5.0.0"
      ) ],
      consumes: [ Coordinator::Write::Candidates::ImpactObservationV1.new(
        impact_key: "schema:orders",
        value: "v1"
      ) ],
      may_affect: [],
      assumes: []
    )
  end

  def reference(type, revision)
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-91919191919#{revision}",
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-index",
      stream_revision: revision
    )
  end
end
