# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::CandidateImpactPolicyProposal do
  subject(:contract) { described_class.new }

  let(:preparer) { Coordinator::Write::Operations::PrepareProposeDecisionInterpretation.new }

  it "accepts the exact disabled, advisory, verification-gate, and merge-gate policies" do
    results = Coordinator::Shared::Types::CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS.map do |level|
      input = InterpretationInput.impact_policy(
        level:,
        required_evidence: %w[combined_tests contract_compatibility_review]
      )
      command = preparer.call(input).value!

      contract.call(decision: command.proposed_decision)
    end

    expect(results).to all(be_success)
  end

  it "rejects noncanonical policy meaning, scope, conditions, validity, and enforcement" do
    examples = [
      copy(statement_kind: "preference"),
      copy(value: Coordinator::Write::Interpretations::DecisionValueV1.new(
        exact.value.to_h.merge(items: [ "unknown_review" ])
      )),
      copy(scope: Coordinator::Write::Interpretations::DecisionScopeV1.new(
        exact.scope.to_h.merge(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
      )),
      copy(conditions: Coordinator::Write::Interpretations::DecisionConditionsV1.new(
        exact.conditions.to_h.merge(phases: [ "verification" ])
      )),
      copy(validity: Coordinator::Write::Interpretations::DecisionValidityV1.new(
        exact.validity.to_h.merge(valid_from: "2026-08-24T00:00:00.000000Z")
      )),
      copy(validity: Coordinator::Write::Interpretations::DecisionValidityV1.new(
        exact.validity.to_h.merge(valid_until: "2026-08-24T00:00:00.000000Z")
      )),
      copy(enforcement: Coordinator::Write::Interpretations::DecisionEnforcementV1.new(
        exact.enforcement.to_h.merge(on_violation: "warn")
      ))
    ]

    results = examples.map { contract.call(decision: _1) }

    expect(results).to all(be_failure)
    expect(results.map { _1.errors.to_h.fetch(:decision).keys }).to include(
      include(:statement_kind),
      include(:value),
      include(:scope),
      include(:conditions),
      include(:validity),
      include(:enforcement)
    )
  end

  it "reserves disabled enforcement for the impact-policy topic" do
    decision = copy(
      topic_id: "testing.required_suites",
      enforcement: Coordinator::Write::Interpretations::DecisionEnforcementV1.new(
        exact.enforcement.to_h.merge(level: "disabled")
      )
    )

    result = contract.call(decision:)

    expect(result).to be_failure
    expect(result.errors.to_h.dig(:decision, :enforcement)).to have_key(:level)
  end

  def exact
    @exact ||= preparer.call(
      InterpretationInput.impact_policy(level: "verification_gate")
    ).value!.proposed_decision
  end

  def copy(**attributes)
    Coordinator::Write::Interpretations::SubmittedDecisionV1.new(exact.to_h.merge(attributes))
  end
end
