# frozen_string_literal: true

module MergeSnapshotScenario
  module_function

  def register(prefix:)
    candidate = CandidateScenario.submit(prefix: "#{prefix}-candidate", build_context: false)
    candidate_input = candidate.fetch(:input)
    input = {
      command_id: "cmd-register-#{prefix}",
      actor: { kind: "agent", id: "integrator-1" },
      merge_snapshot_id: "MS-#{prefix}",
      repository_id: "billing",
      target_branch: "main",
      target_base_commit_oid: "a" * 40,
      ordered_candidates: [
        {
          candidate_id: candidate_input.fetch(:candidate_id),
          head_commit_oid: candidate_input.fetch(:head_commit_oid)
        }
      ],
      merge_commit_oid: "9" * 40,
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
end
