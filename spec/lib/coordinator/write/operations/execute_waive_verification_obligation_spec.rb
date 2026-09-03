# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteWaiveVerificationObligation, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "waives an exact open obligation and leaves replay ownership to the registered Command lifecycle" do
    created = CandidateObligationScenario.create_obligation(prefix: "waiver-open")
    input = CandidateObligationScenario.waiver_arguments(
      created:,
      command_id: "cmd-waiver-open"
    )

    completion = execute(input).value!
    replay = execute(input)
    event = waiver_events(created).sole

    expect(replay.failure.code).to eq(:verification_obligation_already_waived)
    expect(completion.data).to have_attributes(
      obligation_id: created.fetch(:payload).obligation_id,
      previous_status: "open",
      status: "waived",
      reason: have_attributes(code: "accepted_risk")
    )
    expect(event.markers).to include(
      "verification-obligation:#{created.fetch(:payload).obligation_id}",
      "verification-obligation-status:waived",
      "command:cmd-waiver-open"
    )
    expect(command_events("cmd-waiver-open")).to be_empty
  end

  it "allows an exact failed obligation to be waived while preserving its failure fact" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "waiver-failed",
      required_evidence: [ "combined_tests" ]
    )
    claim = CandidateObligationScenario.claim_obligation(
      created:,
      prefix: "waiver-failed"
    )
    CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim:,
      command_id: "cmd-waiver-failed-evidence",
      conclusion: "failed"
    )

    completion = execute(
      CandidateObligationScenario.waiver_arguments(
        created:,
        command_id: "cmd-waiver-failed"
      )
    ).value!
    history = lifecycle_events(created)

    expect(completion.data.previous_status).to eq("failed")
    expect(history.map(&:type)).to eq(%w[
      VerificationObligationCreated
      VerificationObligationFailed
      VerificationObligationWaived
    ])
  end

  it "rejects non-user attribution and stale policy or binding without receipts" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "waiver-denials",
      required_evidence: [ "combined_tests" ]
    )
    base = CandidateObligationScenario.waiver_arguments(
      created:,
      command_id: "cmd-waiver-denial"
    )

    non_user = execute(base.merge(command_id: "cmd-waiver-agent", actor: { kind: "agent", id: "agent-a" }))
    stale_binding = execute(
      base.merge(
        command_id: "cmd-waiver-binding",
        obligation_validity_input_digest: CandidateObligationExamples.digest("stale")
      )
    )
    CandidateObligationScenario.correct_policy(
      policy: created.fetch(:policy),
      prefix: "waiver-denials",
      change_set_id: created.dig(:pair, :ids, :change_set_id)
    )
    stale_policy = execute(base.merge(command_id: "cmd-waiver-policy"))

    expect(non_user.failure.code).to eq(:invalid_input)
    expect(stale_binding.failure.code).to eq(:verification_obligation_binding_stale)
    expect(stale_policy.failure.code).to eq(:verification_obligation_policy_stale)
    expect(%w[cmd-waiver-agent cmd-waiver-binding cmd-waiver-policy].flat_map { command_events(_1) }).to be_empty
  end

  it "rejects a satisfied obligation and a second direct waiver" do
    satisfied = CandidateObligationScenario.create_obligation(
      prefix: "waiver-satisfied",
      required_evidence: [ "combined_tests" ]
    )
    claim = CandidateObligationScenario.claim_obligation(
      created: satisfied,
      prefix: "waiver-satisfied"
    )
    CandidateObligationScenario.submit_compatibility_assessment(
      created: satisfied,
      claim:,
      command_id: "cmd-waiver-satisfied-evidence"
    )
    denied = execute(
      CandidateObligationScenario.waiver_arguments(
        created: satisfied,
        command_id: "cmd-waiver-satisfied"
      )
    )

    created = CandidateObligationScenario.create_obligation(
      prefix: "waiver-reuse",
      source_path: "Gemfile.waiver-reuse.lock",
      target_path: "app/services/waiver_reuse.rb"
    )
    input = CandidateObligationScenario.waiver_arguments(
      created:,
      command_id: "cmd-waiver-reuse"
    )
    execute(input).value!
    changed = execute(
      input.merge(reason: { code: "other", summary: "A changed reason." })
    )

    expect(denied.failure.code).to eq(:verification_obligation_terminal)
    expect(changed.failure.code).to eq(:verification_obligation_already_waived)
    expect(waiver_events(created).length).to eq(1)
    expect(command_events("cmd-waiver-reuse")).to be_empty
  end

  private

  def execute(input)
    described_class.new(event_store:).call(input)
  end

  def waiver_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:payload).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationWaived" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def lifecycle_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:payload).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          VerificationObligationCreated VerificationObligationFailed VerificationObligationWaived
        ],
        maximum_count: 3,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
