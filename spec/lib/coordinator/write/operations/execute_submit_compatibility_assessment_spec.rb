# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitCompatibilityAssessment, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }

  it "accepts partial evidence atomically with a receipt and distinct domain/event UUIDv7 identities" do
    created, claim = claimed_obligation("evidence-partial")
    input = assessment_input(created:, claim:, command_id: "cmd-evidence-partial")

    completion = execute(input).value!
    events = evidence_events(created)

    expect(completion.data).to have_attributes(
      obligation_id: created.fetch(:result).obligation_id,
      evidence_kind: "combined_tests",
      conclusion: "passed",
      status: "open",
      outcome_event: nil
    )
    expect(events.map(&:type)).to eq([ "VerificationEvidenceSubmitted" ])
    expect(completion.data.evidence_id).not_to eq(events.sole.id)
    expect(events.sole.markers).to include(
      "verification-evidence:#{completion.data.evidence_id}",
      "verification-evidence-kind:combined_tests",
      "verification-evidence-conclusion:passed",
      "claim:#{claim.claim_id}",
      "claimant:agent-blue"
    )
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "records evidence before the process manager derives satisfied and failed outcomes" do
    satisfied, satisfied_claim = claimed_obligation(
      "evidence-satisfied",
      required_evidence: %w[combined_tests contract_compatibility_review]
    )
    first = assessment_input(
      created: satisfied,
      claim: satisfied_claim,
      command_id: "cmd-evidence-satisfied-1"
    )
    second = assessment_input(
      created: satisfied,
      claim: satisfied_claim,
      command_id: "cmd-evidence-satisfied-2",
      evidence_kind: "contract_compatibility_review"
    )
    expect(execute(first).value!.data.status).to eq("open")
    satisfied_completion = execute(second).value!
    satisfied_trigger = evidence_events(satisfied).last
    process_outcome(satisfied_trigger)

    expect(satisfied_completion.data.status).to eq("open")
    satisfied_events = evidence_events(satisfied)
    expect(satisfied_events.map(&:type)).to eq([
      "VerificationEvidenceSubmitted",
      "VerificationEvidenceSubmitted",
      "VerificationObligationEvidenceSelected",
      "VerificationObligationEvidenceSelected",
      "VerificationObligationSatisfied"
    ])
    expect(satisfied_events.drop(2).map(&:correlation_id).uniq).to eq([ satisfied_trigger.correlation_id ])

    failed, failed_claim = claimed_obligation(
      "evidence-failed",
      source_path: "package-lock.json",
      target_path: "app/services/shipping.rb"
    )
    failure_input = assessment_input(
      created: failed,
      claim: failed_claim,
      command_id: "cmd-evidence-failed",
      conclusion: "failed"
    )
    failed_completion = execute(failure_input).value!
    process_outcome(evidence_events(failed).sole)

    expect(failed_completion.data.status).to eq("open")
    expect(evidence_events(failed).map(&:type)).to eq([
      "VerificationEvidenceSubmitted",
      "VerificationObligationEvidenceSelected",
      "VerificationObligationFailed"
    ])
  end

  it "records inconclusive evidence and leaves replay ownership to the registered Command lifecycle" do
    created, claim = claimed_obligation("evidence-idempotency")
    input = assessment_input(
      created:,
      claim:,
      command_id: "cmd-evidence-idempotency",
      conclusion: "inconclusive"
    )

    expect(execute(input)).to be_success
    replay = execute(input)
    changed = execute(input.merge(assessment: input.fetch(:assessment).merge(run_id: "changed-run")))
    duplicate = execute(input.merge(command_id: "cmd-evidence-duplicate"))

    expect(replay.failure.code).to eq(:verification_evidence_already_submitted)
    expect(changed).to be_success
    expect(duplicate.failure.code).to eq(:verification_evidence_already_submitted)
    expect(evidence_events(created).map(&:type)).to eq(
      [ "VerificationEvidenceSubmitted", "VerificationEvidenceSubmitted" ]
    )
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "denies stale policy, claim fences, owners, candidate bindings, terminal histories, and expired claims without receipts" do
    created, claim = claimed_obligation("evidence-denials")
    base = assessment_input(created:, claim:, command_id: "cmd-evidence-denial")

    stale_fence = execute(
      base.merge(
        command_id: "cmd-evidence-stale-fence",
        claim: base.fetch(:claim).merge(fencing_token: claim.fencing_token + 1)
      )
    )
    wrong_owner = execute(
      base.merge(command_id: "cmd-evidence-wrong-owner", actor: { kind: "agent", id: "agent-green" })
    )
    stale_binding = execute(
      base.merge(
        command_id: "cmd-evidence-stale-binding",
        binding: base.fetch(:binding).merge(
          source_candidate: base.dig(:binding, :source_candidate).merge(head_commit_oid: "f" * 40)
        )
      )
    )
    CandidateObligationScenario.correct_policy(
      policy: created.fetch(:policy),
      prefix: "evidence-denials",
      change_set_id: created.dig(:pair, :ids, :change_set_id)
    )
    stale_policy = execute(base.merge(command_id: "cmd-evidence-stale-policy"))

    expect(stale_fence.failure.code).to eq(:verification_obligation_claim_stale)
    expect(wrong_owner.failure.code).to eq(:verification_obligation_claim_not_owned)
    expect(stale_binding.failure.code).to eq(:verification_obligation_binding_stale)
    expect(stale_policy.failure.code).to eq(:verification_obligation_policy_stale)
    expect(%w[
      cmd-evidence-stale-fence cmd-evidence-wrong-owner cmd-evidence-stale-binding
      cmd-evidence-stale-policy
    ].flat_map { command_events(_1) }).to be_empty
  end

  it "treats exact claim expiry as expired" do
    Timecop.freeze(Time.utc(2026, 8, 24, 8, 30, 0)) do
      created, claim = claimed_obligation("evidence-expired", duration: 30)
      input = assessment_input(created:, claim:, command_id: "cmd-evidence-expired")

      Timecop.travel(Time.iso8601(claim.expires_at)) do
        result = execute(input)

        expect(result.failure.code).to eq(:verification_obligation_claim_expired)
        expect(command_events(input.fetch(:command_id))).to be_empty
      end
    end
  end

  it "accepts concurrent evidence and converges process redelivery on one terminal outcome" do
    created, claim = claimed_obligation(
      "evidence-race",
      required_evidence: [ "combined_tests" ]
    )
    inputs = %w[blue green].map do |suffix|
      assessment_input(
        created:,
        claim:,
        command_id: "cmd-evidence-race-#{suffix}",
        run_id: "run-#{suffix}",
        result_salt: suffix
      )
    end

    results = inputs.map do |input|
      Thread.new { execute(input) }
    end.map(&:value)

    expect(results).to all(be_success)
    evidence_events(created).select { _1.type == "VerificationEvidenceSubmitted" }.each do |event|
      process_outcome(event)
      process_outcome(event)
    end
    expect(evidence_events(created).map(&:type)).to contain_exactly(
      "VerificationEvidenceSubmitted",
      "VerificationEvidenceSubmitted",
      "VerificationObligationEvidenceSelected",
      "VerificationObligationSatisfied"
    )
    expect(inputs.flat_map { command_events(_1.fetch(:command_id)) }).to be_empty
  end

  it "denies absent, unclaimed, non-required, and already-terminal obligations without receipts" do
    absent_input = VerificationEvidenceExamples.raw_input.merge(command_id: "cmd-evidence-absent")
    expect(execute(absent_input).failure.code).to eq(:verification_obligation_not_found)

    unclaimed = CandidateObligationScenario.create_obligation(prefix: "evidence-unclaimed")
    synthetic_claim = VerificationEvidenceExamples.claim
    unclaimed_input = assessment_input(
      created: unclaimed,
      claim: synthetic_claim,
      command_id: "cmd-evidence-unclaimed"
    )
    expect(execute(unclaimed_input).failure.code).to eq(:verification_obligation_unclaimed)

    created, claim = claimed_obligation(
      "evidence-not-required",
      source_path: "yarn.lock",
      target_path: "app/services/catalog.rb"
    )
    not_required = assessment_input(
      created:,
      claim:,
      command_id: "cmd-evidence-not-required",
      evidence_kind: "security_review"
    )
    expect(execute(not_required).failure.code).to eq(:verification_evidence_kind_not_required)

    terminal, terminal_claim = claimed_obligation(
      "evidence-terminal",
      required_evidence: [ "combined_tests" ],
      source_path: "Cargo.lock",
      target_path: "app/services/search.rb"
    )
    first = assessment_input(
      created: terminal,
      claim: terminal_claim,
      command_id: "cmd-evidence-terminal-first"
    )
    second = assessment_input(
      created: terminal,
      claim: terminal_claim,
      command_id: "cmd-evidence-terminal-second",
      run_id: "run-terminal-second",
      result_salt: "terminal-second"
    )
    expect(execute(first)).to be_success
    process_outcome(evidence_events(terminal).sole)
    expect(execute(second).failure.code).to eq(:verification_obligation_terminal)

    denied_commands = %w[
      cmd-evidence-absent cmd-evidence-unclaimed cmd-evidence-not-required
      cmd-evidence-terminal-second
    ]
    expect(denied_commands.flat_map { command_events(_1) }).to be_empty
  end

  it "accepts at most thirty-two distinct evidence facts" do
    created, claim = claimed_obligation(
      "evidence-limit",
      required_evidence: %w[combined_tests contract_compatibility_review]
    )
    32.times do |index|
      input = assessment_input(
        created:,
        claim:,
        command_id: "cmd-evidence-limit-#{index}",
        run_id: "run-limit-#{index}",
        result_salt: "limit-#{index}"
      )
      expect(execute(input)).to be_success
    end
    overflow = assessment_input(
      created:,
      claim:,
      command_id: "cmd-evidence-limit-overflow",
      run_id: "run-limit-overflow",
      result_salt: "limit-overflow"
    )

    expect(execute(overflow).failure.to_h).to include(
      code: :verification_evidence_limit_reached,
      details: include(maximum_count: 32)
    )
    expect(evidence_events(created).length).to eq(32)
    expect(command_events(overflow.fetch(:command_id))).to be_empty
  end

  private

  def claimed_obligation(prefix, required_evidence: nil, duration: 300, **paths)
    created = CandidateObligationScenario.create_obligation(prefix:, required_evidence:, **paths)
    claim = CandidateObligationScenario.claim_obligation(created:, prefix:, duration:)
    [ created, claim ]
  end

  def assessment_input(created:, claim:, command_id:, **options)
    CandidateObligationScenario.compatibility_assessment_arguments(
      created:,
      claim:,
      command_id:,
      **options
    )
  end

  def execute(input)
    described_class.new(event_store:).call(input)
  end

  def evidence_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:result).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          VerificationEvidenceSubmitted VerificationObligationEvidenceSelected
          VerificationObligationSatisfied VerificationObligationFailed
        ],
        maximum_count: 34,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end

  def process_outcome(event)
    Coordinator::Processes::ProcessManagers::VerificationEvidenceOutcome.new(event_store:).call(event)
  end
end
