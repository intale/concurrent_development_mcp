# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::CandidateObligations::Create do
  subject(:decider) { described_class.new }

  let(:source) do
    CandidateObligationExamples.evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "Gemfile.lock",
      produces: [ "dependency:rubygems:rails" ]
    )
  end
  let(:target) do
    CandidateObligationExamples.evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "app/services/checkout.rb",
      observed_paths: [ "Gemfile.lock" ],
      assumes: [ "dependency:rubygems:rails" ]
    )
  end
  let(:command) { CandidateObligationExamples.command(source:, target:) }

  it "IMP-02-GATE-01 creates four cohesive compatibility-obligation facts" do
    decision = decide

    expect(decision).to have_attributes(outcome: "created")
    expect(decision.plan.writes).to all(
      have_attributes(stream: have_attributes(
        context: "DevelopmentIntegration",
        stream_name: "VerificationObligation",
        stream_id: command.obligation_id
      ))
    )
    expect(decision.obligation).to have_attributes(
      obligation_id: command.obligation_id,
      kind: "candidate_compatibility",
      required_evidence: %w[combined_tests contract_compatibility_review],
      enforcement: "merge_gate"
    )
    expect(decision.obligation.reasons).to eq(%w[
      observed_input_changed
      semantic_key_match
    ])
    expect(decision.plan.events.drop(1)).to contain_exactly(
      have_attributes(obligation_id: command.obligation_id, change_set_id: "CS-obligation"),
      have_attributes(obligation_id: command.obligation_id, candidate_id: source.subject.candidate_id),
      have_attributes(obligation_id: command.obligation_id, candidate_id: target.subject.candidate_id)
    )
  end

  it "IMP-02-DUPLICATE-01 replays an exact existing obligation" do
    created = decide.obligation
    original = CandidateObligationExamples.definition(created:, source:, target:)

    replay = decide(existing: original)

    expect(replay).to have_attributes(
      outcome: "replayed",
      plan: nil,
      obligation: original
    )
  end

  it "returns strict no-event outcomes for stale, non-gating, and inactive policy" do
    outcomes = %w[stale non_gating inactive].map do |status|
      decide(policy: CandidateObligationExamples.policy(status:)).outcome
    end

    expect(outcomes).to eq(%w[stale_policy non_gating_policy inactive_policy])
  end

  it "IMP-02-NOMATCH-01 returns a successful no-op for a routed bucket collision" do
    unrelated = CandidateObligationExamples.evidence(
      candidate_id: "CAN-unrelated",
      registry_revision: 2,
      path: "lib/unrelated.rb",
      observed_paths: [ "config/unrelated.yml" ],
      consumes: [ "contract:unrelated:v1" ]
    )
    unrelated_command = CandidateObligationExamples.command(source:, target: unrelated)

    decision = decide(target: unrelated, command: unrelated_command)

    expect(decision).to have_attributes(outcome: "no_match", plan: nil, obligation: nil)
  end

  def decide(
    source: self.source,
    target: self.target,
    command: self.command,
    policy: CandidateObligationExamples.policy,
    existing: nil
  )
    state = Coordinator::Write::Domain::CandidateObligations::State.new(
      source:,
      target:,
      policy:,
      existing:
    )
    decider.call(state:, command:).value!
  end
end
