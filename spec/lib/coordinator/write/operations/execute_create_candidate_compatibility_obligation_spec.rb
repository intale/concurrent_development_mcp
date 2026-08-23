# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteCreateCandidateCompatibilityObligation, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "IMP-02-GATE-01 creates one exact policy-bound obligation with persisted tracing" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-gate")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-gate",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = CandidateObligationScenario.invocation(pair:, policy:)

    result = operation.call(invocation)

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      outcome: "created",
      obligation_id: invocation.command.obligation_id,
      event: have_attributes(
        type: "VerificationObligationCreated",
        stream_id: invocation.command.obligation_id,
        stream_revision: 0
      )
    )
    physical = obligation_events(invocation.command.obligation_id).sole
    obligation = CandidateObligationScenario.load(physical)
    expect(obligation).to have_attributes(
      kind: "candidate_compatibility",
      status: "open",
      change_set_id: pair.dig(:ids, :change_set_id),
      enforcement: "merge_gate",
      required_evidence: %w[combined_tests contract_compatibility_review],
      rule_version: CandidateObligationScenario::RULE_VERSION
    )
    expect(obligation.reasons.map(&:kind)).to eq(%w[
      observed_input_changed
      semantic_key_match
    ])
    expect(physical.markers).to include(
      "verification-obligation:#{invocation.command.obligation_id}",
      "source-candidate:#{pair.dig(:source, :candidate_id)}",
      "target-candidate:#{pair.dig(:target, :candidate_id)}",
      "enforcement:merge_gate",
      "decision:#{policy.fetch(:head).decision_id}"
    )
    expect(physical.causation_id).to eq(invocation.caused_by.id)
    expect(physical.correlation_id).to eq(invocation.caused_by.correlation_id)
    expect(physical.metadata).not_to have_key("correlation_id")
    expect(command_events(invocation.command.command_id)).to be_empty
  end

  it "IMP-02-DUPLICATE-01 replays one exact creation" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-replay")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-replay",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = CandidateObligationScenario.invocation(pair:, policy:)

    first = operation.call(invocation)
    replay = operation.call(invocation)

    expect(first.value!.outcome).to eq("created")
    expect(replay.value!).to have_attributes(
      outcome: "replayed",
      obligation_id: invocation.command.obligation_id,
      event: first.value!.event
    )
    expect(obligation_events(invocation.command.obligation_id).length).to eq(1)
  end

  it "IMP-02-DISABLED-01 and IMP-02-ADVISORY-01 create no obligation facts" do
    results = %w[disabled advisory].map do |level|
      prefix = "obligation-#{level}"
      pair = CandidateObligationScenario.submit_pair(
        prefix:,
        source_path: "#{prefix}/Gemfile.lock",
        target_path: "#{prefix}/app/services/checkout.rb"
      )
      policy = CandidateObligationScenario.activate_policy(
        prefix:,
        change_set_id: pair.dig(:ids, :change_set_id),
        level:
      )
      invocation = CandidateObligationScenario.invocation(pair:, policy:)
      [ operation.call(invocation), invocation ]
    end

    expect(results.map { _1.first.value!.outcome }).to eq(%w[
      non_gating_policy
      non_gating_policy
    ])
    results.each do |result, invocation|
      expect(result.value!.event).to be_nil
      expect(obligation_events(invocation.command.obligation_id)).to be_empty
    end
  end

  it "IMP-02-NOMATCH-01 treats a routed exact mismatch as a successful no-op" do
    pair = CandidateObligationScenario.submit_pair(
      prefix: "obligation-no-match",
      source_path: "lib/source.rb",
      target_path: "lib/target.rb",
      observed_source: false,
      source_key: "contract:source:v1",
      target_key: "contract:target:v1"
    )
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-no-match",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = CandidateObligationScenario.invocation(pair:, policy:)

    result = operation.call(invocation)

    expect(result.value!).to have_attributes(
      outcome: "no_match",
      event: nil
    )
    expect(obligation_events(invocation.command.obligation_id)).to be_empty
  end

  it "IMP-02-STALE-POLICY-01 rejects an old partition and accepts the corrected exact head" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-stale")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-stale",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    stale_invocation = CandidateObligationScenario.invocation(pair:, policy:)
    corrected = CandidateObligationScenario.correct_policy(
      policy:,
      prefix: "obligation-stale",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    current_invocation = CandidateObligationScenario.invocation(pair:, policy: corrected)

    stale = operation.call(stale_invocation)
    current = operation.call(current_invocation)

    expect(stale.value!).to have_attributes(outcome: "stale_policy", event: nil)
    expect(current.value!).to have_attributes(outcome: "created")
    expect(CandidateObligationScenario.load(obligation_events(current_invocation.command.obligation_id).sole)).to have_attributes(
      enforcement: "verification_gate",
      required_evidence: [ "combined_tests" ],
      policy: have_attributes(head: corrected.fetch(:head))
    )
    expect(obligation_events(stale_invocation.command.obligation_id)).to be_empty
  end

  it "serializes a concurrent duplicate command to one creation and one replay" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-race")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-race",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = CandidateObligationScenario.invocation(pair:, policy:)

    results = 2.times.map do
      Thread.new { described_class.new(event_store:).call(invocation) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(results.map { _1.value!.outcome }.sort).to eq(%w[created replayed])
    expect(obligation_events(invocation.command.obligation_id).length).to eq(1)
  end

  def obligation_events(obligation_id)
    CandidateObligationScenario.obligation_events(obligation_id)
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end
end
