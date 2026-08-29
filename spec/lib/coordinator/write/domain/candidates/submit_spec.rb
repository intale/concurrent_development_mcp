# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Candidates::Submit do
  subject(:decider) { described_class.new }

  it "CAN-01-SUBMIT-01 produces the complete manifest-only plan" do
    command = prepared_command
    result = decide(command:)

    expect(result).to be_success
    plan = result.value!
    expect(plan.events.map(&:class)).to eq([
      Coordinator::Write::Events::CandidateSubmittedV2,
      Coordinator::Write::Events::CandidateChangeManifestCapturedV1,
      Coordinator::Write::Events::CandidateHeadRegisteredV1,
      Coordinator::Write::Events::CandidateAttachedToAttemptV1
    ])
    expect(plan.writes.map(&:stream)).to eq([
      streams.candidate("CAN-41"),
      streams.candidate("CAN-41"),
      streams.candidate_head(head_identity.registry_id),
      streams.attempt("A-18")
    ])
    expect(plan.events.first).to have_attributes(
      manifest_digest: command.manifest.digest,
      build_context_digest: nil,
      lease_references: [ lease_reference ],
      evidence_status: "attributed_unverified"
    )
    expect(plan.events.last.candidate_event).to eq(candidate_event)
  end

  it "CAN-01-CONTEXT-01 adds exactly one build-context fact" do
    command = prepared_command(build_context: build_context_input)

    events = decide(command:).value!.events

    expect(events.map(&:class)).to eq([
      Coordinator::Write::Events::CandidateSubmittedV2,
      Coordinator::Write::Events::CandidateChangeManifestCapturedV1,
      Coordinator::Write::Events::CandidateBuildContextCapturedV1,
      Coordinator::Write::Events::CandidateHeadRegisteredV1,
      Coordinator::Write::Events::CandidateAttachedToAttemptV1
    ])
    expect(events.first.build_context_digest).to eq(command.build_context.digest)
    expect(events.fetch(2).build_context_digest).to eq(command.build_context.digest)
  end

  it "denies an existing Candidate or registered head without a plan" do
    candidate_denial = decide(existing_candidate: candidate_event)
    head_denial = decide(existing_head: head_event)

    expect(candidate_denial.failure.code).to eq(:candidate_id_already_used)
    expect(head_denial.failure.code).to eq(:candidate_head_already_registered)
  end

  it "denies inactive, mismatched-scope, and non-owner Attempts" do
    inactive = attempt_state(status: "authorized")
    wrong_scope = attempt_state(work_item_id: "W-other")
    wrong_owner = attempt_state(agent_id: "agent-other")

    expect(decide(attempt: inactive).failure.code).to eq(:attempt_not_active)
    expect(decide(attempt: wrong_scope).failure.code).to eq(:attempt_scope_mismatch)
    expect(decide(attempt: wrong_owner).failure.code).to eq(:attempt_actor_mismatch)
  end

  it "denies incomplete, stale, and inactive lease observations" do
    command = prepared_command
    mismatched = copy_command(
      command,
      leases: [ Coordinator::Write::Candidates::LeaseObservationV1.new(
        resource_id: lease_reference.resource_id,
        lease_id: uuid("9"),
        fencing_token: 1
      ) ]
    )
    expired = current_lease(expires_at: "2026-08-23T11:29:59.000000Z")

    expect(decide(command: mismatched).failure.code).to eq(:lease_observations_mismatch)
    expect(decide(current_leases: []).failure.code).to eq(:lease_not_active)
    expect(decide(current_leases: [ expired ]).failure.code).to eq(:lease_not_active)
  end

  it "denies undeclared resources and mismatched old-side base evidence" do
    undeclared_command = prepared_command(
      files: [ manifest_file(old_path: "lib/other.rb", new_path: "lib/other.rb") ]
    )
    mismatched_reference = Coordinator::Write::LeaseReferenceV2.new(
      lease_reference.to_h.merge(base_blob_oid: "e" * 40)
    )
    mismatched_attempt = attempt_state(reference: mismatched_reference)
    mismatched_lease = current_lease(reference: mismatched_reference, base_blob_oid: "e" * 40)

    expect(decide(command: undeclared_command).failure.code).to eq(:actual_write_set_not_authorized)
    expect(
      decide(attempt: mismatched_attempt, current_leases: [ mismatched_lease ]).failure.code
    ).to eq(:manifest_base_evidence_mismatch)
  end

  it "authorizes manifest files covered by a leased directory without comparing tree evidence to blobs" do
    reference = lease_reference_for(kind: "directory", path: "lib", base_blob_oid: "e" * 40)
    command = prepared_command(
      reference:,
      files: [ manifest_file(old_path: "lib/nested/example.rb", new_path: "lib/nested/example.rb") ]
    )

    result = decide(
      command:,
      attempt: attempt_state(reference:),
      current_leases: [ current_lease(reference:) ]
    )

    expect(result).to be_success
    expect(result.value!.events.first.lease_references).to eq([ reference ])
  end

  def decide(
    command: prepared_command,
    attempt: active_attempt,
    current_leases: [ current_lease ],
    existing_candidate: nil,
    existing_head: nil
  )
    decider.call(
      state: Coordinator::Write::Domain::Candidates::SubmissionState.new(
        existing_candidate:,
        existing_head:,
        attempt:,
        current_leases:
      ),
      command:,
      submitted_at: "2026-08-23T11:30:00.000000Z",
      candidate_event:,
      head_identity:
    )
  end

  def prepared_command(files: [ manifest_file ], build_context: nil, reference: lease_reference)
    input = {
      command_id: "cmd-candidate-1",
      actor: { kind: "agent", id: "agent-7" },
      candidate_id: "CAN-41",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-18",
      repository_id:,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      lease_set_id: uuid("1"),
      leases: [
        {
          resource_id: reference.resource_id,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      ],
      change_manifest: { collector_version: "git-evidence-v1", files: }
    }
    input[:build_context] = build_context if build_context
    result = Coordinator::Write::Operations::PrepareSubmitCandidate.new.call(input)
    raise result.failure.inspect if result.failure?

    result.value!
  end

  def active_attempt
    attempt_state
  end

  def attempt_state(
    status: "active",
    reference: lease_reference,
    work_item_id: "W-1",
    agent_id: "agent-7"
  )
    Coordinator::Write::Domain::Attempts::State.new(
      attempt_id: "A-18",
      change_set_id: "CS-1",
      work_item_id:,
      agent_id:,
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id:,
          object_format: "sha1",
          commit_oid: "a" * 40
        )
      ],
      lease_set_id: uuid("1"),
      lease_repository_id: repository_id,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_resources: [ reference ],
      lease_reserved_at: "2026-08-23T11:00:00.000000Z",
      lease_renewed_at: nil,
      lease_expires_at: "2026-08-23T12:00:00.000000Z",
      lease_released_at: nil,
      status:
    )
  end

  def copy_command(command, **changes)
    Coordinator::Write::Commands::SubmitCandidate.new(
      command.to_h.merge(
        actor: command.actor,
        leases: command.leases,
        manifest: command.manifest,
        build_context: command.build_context,
        actual_resources: command.actual_resources
      ).merge(changes)
    )
  end

  def current_lease(
    reference: lease_reference,
    expires_at: "2026-08-23T12:00:00.000001Z",
    base_blob_oid: reference.base_blob_oid
  )
    state = Coordinator::Write::Domain::ResourceLeases::State.new(
      lease_id: reference.lease_id,
      lease_set_id: uuid("1"),
      resource_id: reference.resource_id,
      resource_key: nil,
      resource_key_hash: nil,
      resource_kind: reference.resource_kind,
      resource_path: reference.resource_path,
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      mode: "exclusive",
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-18",
      agent_id: "agent-7",
      repository_id:,
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid:,
      fencing_token: reference.fencing_token,
      acquired_at: "2026-08-23T11:00:00.000000Z",
      renewed_at: nil,
      expires_at:,
      released_at: nil,
      expired_at: nil
    )
    Coordinator::Write::CurrentLeaseObservationV2.new(reference:, state:)
  end

  def lease_reference
    @lease_reference ||= lease_reference_for(
      kind: "file",
      path: "lib/example.rb",
      base_blob_oid: "c" * 40
    )
  end

  def lease_reference_for(kind:, path:, base_blob_oid:)
    Coordinator::Write::LeaseReferenceV2.new(
      lease_id: uuid("2"),
      resource_id: kind == "file" ? uuid("5") : uuid("6"),
      resource_kind: kind,
      resource_path: path,
      base_blob_oid:,
      fencing_token: 1
    )
  end

  def head_identity
    @head_identity ||= Coordinator::Write::Candidates::HeadIdentityBuilder.new.call(
      repository_id:,
      object_format: "sha1",
      head_commit_oid: "b" * 40
    )
  end

  def candidate_event
    @candidate_event ||= Coordinator::Write::EventReference.new(
      event_id: uuid("3"),
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-41",
      stream_revision: 0
    )
  end

  def head_event
    Coordinator::Write::EventReference.new(
      event_id: uuid("4"),
      type: "CandidateHeadRegistered",
      stream_context: "DevelopmentIntegration",
      stream_name: "CandidateHead",
      stream_id: head_identity.registry_id,
      stream_revision: 0
    )
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end

  def manifest_file(old_path: "lib/example.rb", new_path: old_path)
    {
      status: "modified",
      old_path:,
      new_path:,
      old_blob_oid: "c" * 40,
      new_blob_oid: "d" * 40,
      old_mode: "100644",
      new_mode: "100644"
    }
  end

  def build_context_input
    {
      collector_version: "build-context-v1",
      inputs: [ { kind: "runtime_version", path: ".ruby-version", blob_oid: "e" * 40 } ],
      environment: [ { name: "ruby", value: "4.0.6" } ]
    }
  end

  def uuid(suffix)
    "01919191-9191-7191-8191-91919191919#{suffix}"
  end

  def repository_id
    RepositoryScenario::DEFAULT_REPOSITORY_ID
  end
end
