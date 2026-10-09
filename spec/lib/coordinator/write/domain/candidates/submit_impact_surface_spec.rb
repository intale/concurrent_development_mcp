# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Candidates::SubmitImpactSurface do
  subject(:decider) { described_class.new }

  it "IMP-02-REGISTER-01 produces the exact surface and registry facts" do
    result = decide

    expect(result).to be_success
    expect(result.value!.writes.map(&:stream)).to eq([
      streams.candidate_impact_surface(surface_id),
      streams.candidate("CAN-41")
    ])
    surface, assignment = result.value!.events
    expect(surface).to have_attributes(
      surface_id:,
      candidate_id: "CAN-41",
      evidence_revision: 1,
      produces: command.surface.produces,
      consumes: command.surface.consumes,
      may_affect: command.surface.may_affect,
      assumes: command.surface.assumes
    )
    expect(assignment).to have_attributes(
      candidate_id: "CAN-41",
      surface_id:
    )
  end

  it "denies absent/mismatched Candidate identity and source evidence" do
    absent = decide(evidence: nil)
    identity = decide(command: copy_command(repository_id: RepositoryScenario.repository_id("other")))
    evidence = decide(command: copy_command(manifest_digest: "sha256:#{"f" * 64}"))

    expect(absent.failure.code).to eq(:candidate_not_found)
    expect(identity.failure.code).to eq(:candidate_impact_identity_mismatch)
    expect(evidence.failure.code).to eq(:candidate_impact_source_evidence_mismatch)
  end

  it "denies a second initial surface" do
    result = decide(existing_surface: event_reference)

    expect(result.failure.code).to eq(:candidate_impact_surface_already_recorded)
    expect(result.failure.details.fetch(:existing_event)).to eq(event_reference.to_h)
  end

  def decide(
    command: self.command,
    evidence: self.evidence,
    existing_surface: nil
  )
    decider.call(
      state: Coordinator::Write::Domain::Candidates::ImpactSurfaceState.new(
        evidence:,
        existing_surface:
      ),
      command:,
      surface_id:
    )
  end

  def evidence
    Coordinator::Write::Candidates::ImpactSurfaceEvidenceV2.new(candidate: candidate_state)
  end

  def candidate_state
    Coordinator::Write::Candidates::StateV2.new(
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      agent_id: "agent-7",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      intention_set_id: "01919191-9191-7191-8191-919191919191",
      manifest_digest: "sha256:#{"a" * 64}",
      build_context_digest: nil,
      manifest:,
      build_context: nil,
      submission_event: candidate_event,
      manifest_event:,
      build_context_event: nil,
      surface_id: nil,
      surface_assignment_event: nil,
      latest_revision: 8
    )
  end

  def command
    @command ||= Coordinator::Write::Operations::PrepareSubmitCandidateImpactSurface.new
      .call(input)
      .value!
  end

  def copy_command(**changes)
    Coordinator::Write::Commands::SubmitCandidateImpactSurface.new(command.to_h.merge(changes))
  end

  def input
    {
      command_id: "cmd-impact-1",
      actor: { kind: "agent", id: "analyzer-7" },
      candidate_id: "CAN-41",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      head_commit_oid: "b" * 40,
      manifest_digest: "sha256:#{"a" * 64}",
      analyzer_version: "impact-v1",
      surface: {
        produces: [ { impact_key: "runtime:ruby", before: "3.3", after: "4.0" } ],
        consumes: [],
        may_affect: [],
        assumes: []
      }
    }
  end

  def manifest
    Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id: "CAN-41",
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

  def event_reference
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919193",
      type: "CandidateImpactSurfaceDerived",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-41",
      stream_revision: 3
    )
  end

  def candidate_event
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919194",
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-41",
      stream_revision: 0
    )
  end

  def manifest_event
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919195",
      type: "CandidateChangeManifestCaptured",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-41",
      stream_revision: 1
    )
  end

  def surface_event
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919196",
      type: "CandidateImpactSurfaceDerived",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-41",
      stream_revision: 2
    )
  end

  def surface_id
    "01919191-9191-7191-8191-919191919197"
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end
end
