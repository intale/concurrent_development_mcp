# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CandidatesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:candidate_id) { "CAN-candidate-project" }
  let(:repository_id) { "01a03deb-6f55-74ba-bcc0-afd02e7b14dc" }
  let(:stream) { Coordinator::Write::StreamFactory.new.candidate(candidate_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:manifest_digest) { "sha256:#{'a' * 64}" }
  let(:build_context_digest) { "sha256:#{'b' * 64}" }

  it "serves each observed evidence stage and preserves exact source tracing" do
    submitted, manifest, build_context = candidate_events

    projector.call(submitted)
    projector.call(submitted)
    available = repository.fetch(candidate_id)
    expect(available).to have_attributes(
      evidence_status: "attributed_unverified",
      manifest: nil,
      build_context: nil,
      submitted: have_attributes(
        global_position: submitted.global_position,
        causation_id: submitted.causation_id,
        correlation_id: submitted.correlation_id
      )
    )

    projector.call(manifest)
    projector.call(build_context)
    projector.call(build_context)
    projected = repository.fetch(candidate_id)
    expect(projected.manifest).to have_attributes(
      digest: manifest_digest,
      collector: have_attributes(kind: "agent", id: "agent-a", collector_version: "git-evidence-v1"),
      evidence: have_attributes(
        event: have_attributes(event_id: manifest.id, stream_revision: 1),
        global_position: manifest.global_position,
        causation_id: manifest.causation_id,
        correlation_id: manifest.correlation_id
      )
    )
    expect(projected.build_context).to have_attributes(
      digest: build_context_digest,
      evidence: have_attributes(
        event: have_attributes(event_id: build_context.id, stream_revision: 2),
        global_position: build_context.global_position
      )
    )
    expect(projected.to_h.keys & %i[fresh pending projection_status]).to be_empty
    expect(Coordinator::Read::Candidate.count).to eq(1)
    expect(processed_events.count).to eq(3)
  end

  it "rolls back its idempotency claim when manifest evidence precedes submission" do
    submitted, manifest, = candidate_events

    expect { projector.call(manifest) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "CandidateSubmitted must be projected before its manifest"
    )
    expect(processed_events).to be_empty

    projector.call(submitted)
    projector.call(manifest)
    expect(repository.fetch(candidate_id).manifest).not_to be_nil
  end

  it "indexes changed paths, observed inputs, and attributed impact keys idempotently" do
    events = [ *candidate_events, impact_event ]

    events.each { projector.call(_1) }
    events.each { projector.call(_1) }

    record = Coordinator::Read::Candidate.find(candidate_id)
    expect(record.impact_surface).to include(
      "surface_digest" => a_string_matching(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
      "evidence_status" => "attributed_unverified"
    )
    expect(Coordinator::Read::CandidateChangedResource.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::CandidateObservedInput.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(
      Coordinator::Read::CandidateImpactKey.order(:direction).pluck(:direction, :impact_key)
    ).to contain_exactly(
      [ "produces", "contract:payments-api:v2" ],
      [ "consumes", "runtime:ruby" ],
      [ "may_affect", "framework:rails:callbacks" ],
      [ "assumes", "database:postgresql" ]
    )
    expect(processed_events.count).to eq(4)
  end

  def candidate_events
    submitted = candidate_event(submitted_payload, revision: 0, position: 100)
    manifest = candidate_event(
      manifest_payload,
      revision: 1,
      position: 200,
      causation_id: submitted.id
    )
    build_context = candidate_event(
      build_context_payload,
      revision: 2,
      position: 300,
      causation_id: submitted.id
    )
    [ submitted, manifest, build_context ]
  end

  def submitted_payload
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id:,
      change_set_id: "CS-candidate-project",
      work_item_id: "W-candidate-project",
      attempt_id: "A-candidate-project",
      agent_id: "agent-a",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "c" * 40,
      head_commit_oid: "d" * 40,
      checkpoint_kind: "final",
      lease_set_id: "018f0f4d-4e45-7abc-8def-000000000201",
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: "018f0f4d-4e45-7abc-8def-000000000202",
          resource_id: "018f0f4d-4e45-7abc-8def-000000000203",
          resource_kind: "file",
          resource_path: "lib/candidate.rb",
          base_blob_oid: "e" * 40,
          fencing_token: 1
        )
      ],
      manifest_digest:,
      build_context_digest:,
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-30T12:00:00.000000Z"
    )
  end

  def manifest_payload
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id:,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "c" * 40,
      head_commit_oid: "d" * 40,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
      manifest_digest:,
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified",
          old_path: "lib/candidate.rb",
          new_path: "lib/candidate.rb",
          old_blob_oid: "e" * 40,
          new_blob_oid: "f" * 40,
          old_mode: "100644",
          new_mode: "100644"
        )
      ],
      collector: evidence_collector("git-evidence-v1"),
      captured_at: "2026-08-30T12:01:00.000000Z"
    )
  end

  def build_context_payload
    Coordinator::Write::Events::CandidateBuildContextCapturedV1.new(
      candidate_id:,
      repository_id:,
      object_format: "sha1",
      head_commit_oid: "d" * 40,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA,
      build_context_digest:,
      inputs: [
        Coordinator::Write::Candidates::BuildInputV1.new(
          kind: "public_contract",
          path: "lib/candidate.rb",
          blob_oid: "f" * 40
        )
      ],
      environment: [
        Coordinator::Write::Candidates::EnvironmentEntryV1.new(
          name: "RUBY_VERSION",
          value: RUBY_VERSION
        )
      ],
      dependency_graph_digest: "sha256:#{'c' * 64}",
      test_environment_digest: nil,
      collector: evidence_collector("build-context-v1"),
      captured_at: "2026-08-30T12:02:00.000000Z"
    )
  end

  def impact_event
    payload = Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1.new(
      candidate_id:,
      change_set_id: "CS-candidate-project",
      work_item_id: "W-candidate-project",
      attempt_id: "A-candidate-project",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      head_commit_oid: "d" * 40,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ImpactSurfaceDocumentV1::SCHEMA,
      surface_digest: "sha256:#{'d' * 64}",
      manifest_digest:,
      build_context_digest:,
      produces: [
        Coordinator::Write::Candidates::ImpactTransitionV1.new(
          impact_key: "contract:payments-api:v2",
          before: nil,
          after: "available"
        )
      ],
      consumes: [
        Coordinator::Write::Candidates::ImpactObservationV1.new(
          impact_key: "runtime:ruby",
          value: "4.0"
        )
      ],
      may_affect: [
        Coordinator::Write::Candidates::ImpactKeyV1.new(
          impact_key: "framework:rails:callbacks"
        )
      ],
      assumes: [
        Coordinator::Write::Candidates::ImpactAssumptionV1.new(
          impact_key: "database:postgresql",
          predicate: ">= 17"
        )
      ],
      analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
        kind: "agent",
        id: "analyzer-7",
        analyzer_version: "impact-analyzer-v1"
      ),
      evidence_status: "attributed_unverified",
      derived_at: "2026-08-30T12:03:00.000000Z"
    )
    candidate_event(
      payload,
      revision: 3,
      position: 400,
      policy_version: Coordinator::Write::Candidates::ImpactSurfaceDocumentV1::SCHEMA
    )
  end

  def evidence_collector(version)
    Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "agent-a",
      collector_version: version
    )
  end

  def candidate_event(
    payload,
    revision:,
    position:,
    policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
    causation_id: nil
  )
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-candidate-project-#{revision}",
      actor_id: revision == 3 ? "analyzer-7" : "agent-a",
      policy_version:,
      correlation_id:,
      causation_id:,
      markers: [ "candidate:#{candidate_id}", "repository:#{repository_id}" ]
    )
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::Candidates.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "candidates",
      projection_version: 1
    )
  end
end
