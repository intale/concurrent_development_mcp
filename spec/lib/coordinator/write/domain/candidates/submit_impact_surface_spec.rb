# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Candidates::SubmitImpactSurface do
  subject(:decider) { described_class.new }

  it "IMP-01-SURFACE-01 produces one exact attributed surface fact" do
    result = decide

    expect(result).to be_success
    expect(result.value!.writes.map(&:stream)).to eq([ streams.candidate("CAN-41") ])
    expect(result.value!.events.sole).to have_attributes(
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      surface_digest: command.surface.digest,
      manifest_digest: manifest.manifest_digest,
      evidence_status: "attributed_unverified",
      derived_at: "2026-08-23T15:00:00.000000Z"
    )
  end

  it "denies absent/mismatched Candidate identity and source evidence" do
    absent = decide(submission: nil)
    identity = decide(command: copy_command(repository_id: "other"))
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
    submission: self.submission,
    manifest: self.manifest,
    build_context: nil,
    existing_surface: nil
  )
    decider.call(
      state: Coordinator::Write::Domain::Candidates::ImpactSurfaceState.new(
        submission:,
        manifest:,
        build_context:,
        existing_surface:
      ),
      command:,
      derived_at: "2026-08-23T15:00:00.000000Z"
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
      repository_id: "billing",
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

  def submission
    Coordinator::Write::Events::CandidateSubmittedV1.new(
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      agent_id: "agent-7",
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
      build_context_digest: nil,
      evidence_status: "attributed_unverified",
      submitted_at: "2026-08-23T14:00:00.000000Z"
    )
  end

  def manifest
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: "CAN-41",
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
      collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
        kind: "agent",
        id: "agent-7",
        collector_version: "git-v1"
      ),
      captured_at: "2026-08-23T14:00:00.000000Z"
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

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end
end
