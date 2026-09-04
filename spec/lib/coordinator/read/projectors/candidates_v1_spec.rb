# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CandidatesV1, :read_model do
  subject(:projector) do
    described_class.new(submission_loader:, impact_surface_loader:)
  end

  let(:candidate_id) { "CAN-candidate-project" }
  let(:repository_id) { "01a03deb-6f55-74ba-bcc0-afd02e7b14dc" }
  let(:surface_id) { SecureRandom.uuid_v7 }
  let(:stream) { Coordinator::Write::StreamFactory.new.candidate(candidate_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:manifest_digest) { digest("a") }
  let(:build_context_digest) { digest("b") }
  let(:submission_loader) { constant_loader(submission) }
  let(:impact_surface_loader) { constant_loader(impact_source) }

  it "reconstructs the complete submitted Candidate at its terminal fact and stays idempotent" do
    projector.call(submitted_event)
    projector.call(submitted_event)

    projected = repository.fetch(candidate_id)
    expect(projected).to have_attributes(
      evidence_status: "attributed_unverified",
      repository_id:,
      lease_set_id: submission.intention_set_id,
      submitted: have_attributes(
        event: have_attributes(event_id: submitted_event.id, stream_revision: 9),
        global_position: submitted_event.global_position,
        occurred_at: submitted_event.created_at.utc.iso8601(6),
        persisted_at: submitted_event.created_at.utc.iso8601(6)
      )
    )
    expect(projected.manifest).to have_attributes(
      digest: manifest_digest,
      collector: have_attributes(kind: "agent", id: "agent-a", collector_version: "git-evidence-v1"),
      evidence: have_attributes(event: have_attributes(event_id: manifest_event.id, stream_revision: 7))
    )
    expect(projected.build_context).to have_attributes(
      digest: build_context_digest,
      evidence: have_attributes(event: have_attributes(event_id: build_context_event.id, stream_revision: 8))
    )
    expect(Coordinator::Read::CandidateChangedResource.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::CandidateObservedInput.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::Candidate.count).to eq(1)
    expect(processed_events.count).to eq(1)
  end

  it "rolls back its idempotency claim when the exact Candidate history is incomplete" do
    failing_loader = Class.new do
      def call(_candidate_id)
        raise Coordinator::Read::InvalidProjectionSource, "Candidate is missing CandidateCommitRangeDeclared"
      end
    end.new
    failing_projector = described_class.new(
      submission_loader: failing_loader,
      impact_surface_loader:
    )

    expect { failing_projector.call(submitted_event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource,
      "Candidate is missing CandidateCommitRangeDeclared"
    )
    expect(processed_events).to be_empty
    expect(Coordinator::Read::Candidate).not_to exist(candidate_id:)
  end

  it "loads the assigned impact surface and indexes its attributed keys idempotently" do
    projector.call(submitted_event)
    projector.call(surface_assignment_event)
    projector.call(surface_assignment_event)

    record = Coordinator::Read::Candidate.find(candidate_id)
    expect(record.impact_surface).to include(
      "surface_digest" => digest("d"),
      "evidence_status" => "attributed_unverified"
    )
    expect(
      Coordinator::Read::CandidateImpactKey.order(:direction).pluck(:direction, :impact_key)
    ).to contain_exactly(
      [ "produces", "contract:payments-api:v2" ],
      [ "consumes", "runtime:ruby" ],
      [ "may_affect", "framework:rails:callbacks" ],
      [ "assumes", "database:postgresql" ]
    )
    expect(repository.fetch(candidate_id).to_h.keys & %i[fresh pending projection_status]).to be_empty
    expect(processed_events.count).to eq(2)
  end

  def submission
    @submission ||= Coordinator::Read::CandidateSubmissionViewV2.new(
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
      intention_set_id: SecureRandom.uuid_v7,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/candidate.rb",
          base_blob_oid: "e" * 40,
          fencing_token: 1
        )
      ],
      manifest_digest:,
      build_context_digest:,
      evidence_status: "attributed_unverified",
      manifest: manifest_payload,
      build_context: build_context_payload,
      submitted_event:,
      manifest_event:,
      build_context_event:
    )
  end

  def manifest_payload
    Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
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
      ]
    )
  end

  def build_context_payload
    Coordinator::Write::Events::CandidateBuildContextCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
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
      ]
    )
  end

  def submitted_event
    @submitted_event ||= projection_event(
      Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:),
      stream:,
      revision: 9,
      position: 300,
      policy_version: nil
    )
  end

  def manifest_event
    @manifest_event ||= projection_event(
      manifest_payload,
      stream:,
      revision: 7,
      position: 200,
      metadata: Coordinator::Write::Metadata::CandidateChangeManifestV2.new(
        **metadata_attributes("candidate-change-manifest/v1"),
        collector: evidence_collector("git-evidence-v1"),
        manifest_digest:
      )
    )
  end

  def build_context_event
    @build_context_event ||= projection_event(
      build_context_payload,
      stream:,
      revision: 8,
      position: 250,
      metadata: Coordinator::Write::Metadata::CandidateBuildContextV2.new(
        **metadata_attributes("candidate-build-context/v1"),
        collector: evidence_collector("build-context-v1"),
        build_context_digest:,
        dependency_graph_digest: digest("c"),
        test_environment_digest: nil
      )
    )
  end

  def surface_assignment_event
    @surface_assignment_event ||= projection_event(
      Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1.new(candidate_id:, surface_id:),
      stream:,
      revision: 10,
      position: 400,
      policy_version: nil
    )
  end

  def impact_source
    payload = Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2.new(
      surface_id:,
      candidate_id:,
      evidence_revision: 1,
      produces: [
        Coordinator::Write::Candidates::ImpactTransitionV1.new(
          impact_key: "contract:payments-api:v2",
          before: nil,
          after: "available"
        )
      ],
      consumes: [ Coordinator::Write::Candidates::ImpactObservationV1.new(impact_key: "runtime:ruby", value: "4.0") ],
      may_affect: [ Coordinator::Write::Candidates::ImpactKeyV1.new(impact_key: "framework:rails:callbacks") ],
      assumes: [
        Coordinator::Write::Candidates::ImpactAssumptionV1.new(
          impact_key: "database:postgresql",
          predicate: ">= 17"
        )
      ]
    )
    event = projection_event(
      payload,
      stream: Coordinator::Write::StreamFactory.new.candidate_impact_surface(surface_id),
      revision: 0,
      position: 350,
      metadata: Coordinator::Write::Metadata::CandidateImpactSurfaceV2.new(
        **metadata_attributes("candidate-impact-surface/v1"),
        analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
          kind: "agent",
          id: "analyzer-7",
          analyzer_version: "impact-analyzer-v1"
        ),
        manifest_digest:,
        build_context_digest:,
        surface_digest: digest("d")
      )
    )
    Coordinator::Read::CandidateImpactSurfaceSourceV2.new(surface: payload, event:)
  end

  def projection_event(payload, stream:, revision:, position:, policy_version: nil, metadata: nil)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-candidate-project-#{revision}",
      actor_id: payload.is_a?(Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2) ? "analyzer-7" : "agent-a",
      policy_version:,
      metadata:,
      correlation_id:,
      markers: [ "candidate:#{candidate_id}", "repository:#{repository_id}" ]
    )
  end

  def metadata_attributes(policy_version)
    {
      command_id: "cmd-candidate-project",
      actor_kind: "agent",
      actor_id: "agent-a",
      recorded_by: "coordinator",
      policy_version:
    }
  end

  def evidence_collector(version)
    Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "agent-a",
      collector_version: version
    )
  end

  def constant_loader(value)
    Class.new do
      def initialize(value)
        @value = value
      end

      def call(_identifier)
        @value
      end
    end.new(value)
  end

  def digest(character)
    "sha256:#{character * 64}"
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
