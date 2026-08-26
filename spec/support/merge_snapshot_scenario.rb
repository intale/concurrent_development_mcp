# frozen_string_literal: true

module MergeSnapshotScenario
  module_function

  def register(prefix:, path: "lib/candidate.rb", head_commit_oid: "b" * 40, complete_work_item: true)
    candidate = CandidateScenario.submit(
      prefix: "#{prefix}-candidate",
      build_context: false,
      path:,
      head_commit_oid:
    )
    candidate = CandidateScenario.complete(candidate) if complete_work_item
    candidate_input = candidate.fetch(:input)
    input = {
      command_id: "cmd-register-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-#{prefix}",
      repository_id: candidate_input.fetch(:repository_id),
      target_branch: "main",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: [
        {
          candidate_id: candidate_input.fetch(:candidate_id),
          head_commit_oid: candidate_input.fetch(:head_commit_oid)
        }
      ],
      merge_commit_oid: oid("merge", prefix),
      producer: { name: "git-merge", version: "2.47.0" },
      run_id: "run-#{prefix}",
      produced_at: "2026-08-24T15:30:00.000001Z"
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRegisterMergeSnapshot, input)
    event = event_store.read(
      streams.merge_snapshot(input.fetch(:merge_snapshot_id)),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
    ).sole
    { input:, completion:, event: }
  end

  def verification_input(registration, prefix:, conclusion: "passed", findings: [])
    input = registration.fetch(:input)
    receipt = registration.fetch(:completion).data
    {
      command_id: "cmd-verify-#{prefix}",
      actor: { kind: "agent", id: "verifier-1" },
      merge_snapshot_id: input.fetch(:merge_snapshot_id),
      binding: {
        snapshot_event: receipt.snapshot_event.to_h,
        snapshot_digest: receipt.snapshot_digest,
        repository_id: input.fetch(:repository_id),
        target_branch: input.fetch(:target_branch),
        object_format: "sha1",
        target_base_commit_oid: input.fetch(:target_base_commit_oid),
        ordered_candidates: input.fetch(:ordered_candidates),
        merge_commit_oid: input.fetch(:merge_commit_oid)
      },
      assessment: {
        evidence_kind: "combined_tests",
        producer: { name: "rspec", version: "3.13.0" },
        run_id: "verification-run-#{prefix}",
        test_suite_digest: "sha256:#{'1' * 64}",
        environment_digest: "sha256:#{'2' * 64}",
        result_digest: "sha256:#{'3' * 64}",
        conclusion:,
        findings:,
        produced_at: "2026-08-24T16:30:00.000001Z"
      }
    }
  end

  def verify(registration, prefix:, conclusion: "passed", findings: [])
    input = verification_input(registration, prefix:, conclusion:, findings:)
    completion = execute(Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification, input)
    event = event_store.read(
      streams.merge_snapshot(input.fetch(:merge_snapshot_id)),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_VERIFIED
    ).first
    { input:, completion:, event:, payload: event && load(event) }
  end

  def register_candidates(prefix:, candidates:)
    first = candidates.first.fetch(:input)
    input = {
      command_id: "cmd-register-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-#{prefix}",
      repository_id: first.fetch(:repository_id),
      target_branch: first.fetch(:target_branch),
      target_base_commit_oid: first.fetch(:base_commit_oid),
      ordered_candidates: candidates.map do |candidate|
        candidate_input = candidate.fetch(:input)
        {
          candidate_id: candidate_input.fetch(:candidate_id),
          head_commit_oid: candidate_input.fetch(:head_commit_oid)
        }
      end,
      merge_commit_oid: oid("merge", prefix),
      producer: { name: "git-merge", version: "2.47.0" },
      run_id: "run-#{prefix}",
      produced_at: "2026-08-24T15:30:00.000001Z"
    }
    completion = execute(Coordinator::Write::Operations::ExecuteRegisterMergeSnapshot, input)
    event = event_store.read(
      streams.merge_snapshot(input.fetch(:merge_snapshot_id)),
      Coordinator::Write::EventQueries::MERGE_SNAPSHOT_REGISTRATION
    ).sole
    { input:, completion:, event: }
  end

  def authorization_input(registration, verification, prefix:, expected_impact_policy: nil)
    registration_receipt = registration.fetch(:completion).data
    verified = verification.fetch(:payload)
    input = registration.fetch(:input)
    {
      command_id: "cmd-authorize-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: input.fetch(:merge_snapshot_id),
      snapshot_binding: {
        registration_event: registration_receipt.snapshot_event.to_h,
        snapshot_digest: registration_receipt.snapshot_digest,
        verification_event: reference(verification.fetch(:event)).to_h,
        verification_digest: verified.verification_digest
      },
      target_base_observation: {
        repository_id: input.fetch(:repository_id),
        target_branch: input.fetch(:target_branch),
        object_format: registration_receipt.object_format,
        commit_oid: input.fetch(:target_base_commit_oid),
        observer: { name: "git-fetch", version: "2.47.0" },
        run_id: "base-observation-#{prefix}",
        observed_at: "2026-08-24T16:45:00.000001Z"
      },
      expected_impact_policy:
    }
  end

  def authorize(registration, verification, prefix:, expected_impact_policy: nil)
    input = authorization_input(
      registration,
      verification,
      prefix:,
      expected_impact_policy:
    )
    completion = execute(Coordinator::Write::Operations::ExecuteRequestMergeAuthorization, input)
    event = event_store.read(
      streams.merge_authorization(completion.data.authorization_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[MergeAuthorizationGranted MergeAuthorizationDenied],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
    { input:, completion:, event:, payload: load(event) }
  end

  def observation_input(registration, authorization, prefix:)
    snapshot = registration.fetch(:input)
    decision = authorization.fetch(:completion).data
    {
      command_id: "cmd-observe-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: snapshot.fetch(:merge_snapshot_id),
      authorization_event: decision.decision_event.to_h,
      authorization_decision_digest: decision.decision_digest,
      repository_id: snapshot.fetch(:repository_id),
      target_branch: snapshot.fetch(:target_branch),
      object_format: "sha1",
      target_before_commit_oid: snapshot.fetch(:target_base_commit_oid),
      target_after_commit_oid: snapshot.fetch(:merge_commit_oid),
      observer: { name: "git-provider-webhook", version: "2026-08" },
      run_id: "merge-observation-#{prefix}",
      observed_at: "2026-08-24T17:30:00.000001Z"
    }
  end

  def expected_policy(policy)
    payload = load(policy.fetch(:decision))
    {
      partition_event: reference(policy.fetch(:partition_event)).to_h,
      head: policy.fetch(:head).to_h,
      definition_digest: payload.definition_digest
    }
  end

  def execute(operation_class, input)
    result = operation_class.new(event_store:).call(input)
    raise result.failure.inspect if result.failure?

    result.value!
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def oid(*parts)
    Coordinator::Shared::CanonicalJson.new.sha256(parts).delete_prefix("sha256:").first(40)
  end
end
