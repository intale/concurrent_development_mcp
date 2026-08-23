# frozen_string_literal: true

RSpec.describe Coordinator::Write::Candidates::ImpactIndexMarkerBuilder do
  subject(:builder) { described_class.new }

  it "derives the frozen version-1 compound bucket markers" do
    markers = builder.call(evidence:, surface:)

    expect(markers).to eq([
      "compound:candidate-impact-index:v1:sha256:6d2d878bd2551adda1fcbcc7911f73b3dc6462d28e9358f75aad78ae5133192e",
      "compound:candidate-impact-index:v1:sha256:539c0caf9bea7ff27b2e324960e557b3f194e70a4f36a527719752ce87a669d0",
      "compound:candidate-impact-index:v1:sha256:d17bab90959d3a38f79b2ee8820effba03bb9abf2ab3d3943761218fd8914f2c",
      "compound:candidate-impact-index:v1:sha256:b005e9c416b1208116f731009da03251680aff69094277e7c8db27693ca138a5",
      "compound:candidate-impact-index:v1:sha256:a05c9eff9000ea9c540b7eb482bd459b96867d577c04c56e477f97b8165b6fa4"
    ].sort_by(&:b))
  end

  def evidence
    Coordinator::Write::Candidates::ImpactSurfaceEvidenceV1.new(
      submission:,
      submission_event: reference("CandidateSubmitted", 0),
      manifest:,
      manifest_event: reference("CandidateChangeManifestCaptured", 1),
      build_context:,
      build_context_event: reference("CandidateBuildContextCaptured", 2)
    )
  end

  def submission
    Coordinator::Write::Events::CandidateSubmittedV1.new(
      candidate_id: "CAN-index",
      change_set_id: "CS-index",
      work_item_id: "W-index",
      attempt_id: "A-index",
      agent_id: "agent-index",
      repository_id: "billing",
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      lease_set_id: "01919191-9191-7191-8191-919191919191",
      lease_policy_version: "coordinator-resource-key/v1",
      lease_references: [ lease_reference ],
      manifest_digest: "sha256:#{"a" * 64}",
      build_context_digest: "sha256:#{"b" * 64}",
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-23T17:00:00.000000Z"
    )
  end

  def manifest
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: "CAN-index",
      repository_id: "billing",
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      evidence_revision: 1,
      policy_version: "candidate-change-manifest/v1",
      manifest_digest: "sha256:#{"a" * 64}",
      files: [ Coordinator::Write::Candidates::ManifestFileV1.new(
        status: "modified",
        old_path: "Gemfile",
        new_path: "Gemfile",
        old_blob_oid: "c" * 40,
        new_blob_oid: "d" * 40,
        old_mode: "100644",
        new_mode: "100644"
      ) ],
      collector: collector,
      captured_at: "2026-08-23T17:00:00.000000Z"
    )
  end

  def build_context
    Coordinator::Write::Events::CandidateBuildContextCapturedV1.new(
      candidate_id: "CAN-index",
      repository_id: "billing",
      object_format: "sha1",
      head_commit_oid: "b" * 40,
      evidence_revision: 1,
      policy_version: "candidate-build-context/v1",
      build_context_digest: "sha256:#{"b" * 64}",
      inputs: [ Coordinator::Write::Candidates::BuildInputV1.new(
        kind: "toolchain_config",
        path: "config/database.yml",
        blob_oid: "e" * 40
      ) ],
      environment: [],
      dependency_graph_digest: nil,
      test_environment_digest: nil,
      collector: collector,
      captured_at: "2026-08-23T17:00:00.000000Z"
    )
  end

  def surface
    Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1.new(
      candidate_id: "CAN-index",
      change_set_id: "CS-index",
      work_item_id: "W-index",
      attempt_id: "A-index",
      repository_id: "billing",
      target_branch: "main",
      object_format: "sha1",
      head_commit_oid: "b" * 40,
      evidence_revision: 1,
      policy_version: "candidate-impact-surface/v1",
      surface_digest: "sha256:#{"c" * 64}",
      manifest_digest: "sha256:#{"a" * 64}",
      build_context_digest: "sha256:#{"b" * 64}",
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
      assumes: [],
      analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
        kind: "agent",
        id: "analyzer-index",
        analyzer_version: "impact-v1"
      ),
      evidence_status: "attributed_unverified",
      derived_at: "2026-08-23T17:01:00.000000Z"
    )
  end

  def collector
    Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "agent-index",
      collector_version: "git-v1"
    )
  end

  def lease_reference
    Coordinator::Write::LeaseReferenceV1.new(
      resource_key_hash: "sha256:#{"1" * 64}",
      resource_key: "key",
      resource_kind: "file",
      resource_path: "Gemfile",
      base_blob_oid: "c" * 40,
      lease_id: "01919191-9191-7191-8191-919191919192",
      fencing_token: 1
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
