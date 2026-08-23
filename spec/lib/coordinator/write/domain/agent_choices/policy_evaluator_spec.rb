# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::AgentChoices::PolicyEvaluator do
  let(:selected_option_id) { "rspec" }

  it "allows a choice when no Decision is effective" do
    evaluation = evaluate(result)

    expect(evaluation).to have_attributes(
      status: "allowed",
      basis: "no_policy",
      effective_decision: nil,
      contributing_decisions: [],
      warnings: [],
      reason_codes: [ "no_active_decision" ]
    )
  end

  it "allows a choice that satisfies the effective Decision" do
    effective = resolved_decision(decision_id: "D-policy", option_id: "rspec")
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "allowed",
      basis: "compliant",
      effective_decision: effective.head,
      contributing_decisions: [ effective.head ],
      warnings: [],
      reason_codes: [ "selected_option_satisfies_decision" ]
    )
  end

  it "allows and identifies an advisory violation" do
    effective = resolved_decision(
      decision_id: "D-advisory",
      option_id: "minitest",
      on_violation: "warn"
    )
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "allowed",
      basis: "advisory_violation",
      effective_decision: effective.head,
      warnings: [ "decision-warning:D-advisory:0198e03a-d112-7000-8000-000000000001" ],
      reason_codes: [ "selected_option_violates_advisory_decision" ]
    )
  end

  it "blocks a violating choice under a blocking Decision" do
    effective = resolved_decision(decision_id: "D-block", option_id: "minitest")
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "blocked",
      basis: "blocking_violation",
      effective_decision: effective.head,
      reason_codes: [ "selected_option_violates_blocking_decision" ]
    )
  end

  it "applies negative named-choice effects with the same closed semantics" do
    effective = resolved_decision(
      decision_id: "D-forbid",
      option_id: "rspec",
      effect: "forbid"
    )
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "blocked",
      basis: "blocking_violation",
      reason_codes: [ "selected_option_violates_blocking_decision" ]
    )
  end

  it "requires confirmation when configured by the violating Decision" do
    effective = resolved_decision(
      decision_id: "D-confirm",
      option_id: "minitest",
      on_violation: "require_confirmation"
    )
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "confirmation_required",
      basis: "confirmation_required",
      reason_codes: [ "selected_option_requires_confirmation" ]
    )
  end

  it "reports tied most-specific Decisions as a conflict" do
    decisions = [
      resolved_decision(decision_id: "D-conflict-a", option_id: "rspec"),
      resolved_decision(
        decision_id: "D-conflict-b",
        option_id: "minitest",
        event_id: "0198e03a-d112-7000-8000-000000000002"
      )
    ]
    evaluation = evaluate(
      result(
        conflict: Coordinator::Write::DecisionContexts::ConflictV1.new(
          decisions:,
          reason: "tied_most_specific"
        )
      )
    )

    expect(evaluation).to have_attributes(
      status: "conflict",
      basis: "decision_conflict",
      effective_decision: nil,
      contributing_decisions: decisions.map(&:head),
      reason_codes: [ "tied_most_specific_decisions" ]
    )
  end

  it "reports unsupported authoritative heads without inventing a policy" do
    unsupported_head = decision_head("D-unsupported")
    evaluation = evaluate(
      result(
        unsupported_dimensions: [ "scope.branch_selectors" ],
        unsupported_decisions: [ unsupported_head ]
      )
    )

    expect(evaluation).to have_attributes(
      status: "unsupported",
      basis: "unsupported_context",
      contributing_decisions: [ unsupported_head ],
      reason_codes: [ "unsupported_decision_context" ]
    )
  end


  it "reports unresolved authoritative heads without inventing a policy" do
    unresolved_head = decision_head(
      "D-unresolved",
      event_id: "0198e03a-d112-7000-8000-000000000003"
    )
    evaluation = evaluate(result(unresolved_decisions: [ unresolved_head ]))

    expect(evaluation).to have_attributes(
      status: "unresolved",
      basis: "unresolved_head",
      contributing_decisions: [ unresolved_head ],
      reason_codes: [ "unresolved_decision_head" ]
    )
  end

  it "reports a non-named effective value as unsupported" do
    effective = resolved_decision(
      decision_id: "D-set",
      option_id: nil,
      value_schema: "string-set/v1"
    )
    evaluation = evaluate(result(effective_decision: effective))

    expect(evaluation).to have_attributes(
      status: "unsupported",
      basis: "unsupported_context",
      effective_decision: effective.head,
      contributing_decisions: [ effective.head ],
      reason_codes: [ "unsupported_decision_context" ]
    )
  end

  def evaluate(resolution)
    described_class.new.call(resolution:, selected_option_id:)
  end

  def result(
    effective_decision: nil,
    conflict: nil,
    unsupported_dimensions: [],
    unsupported_decisions: [],
    unresolved_decisions: []
  )
    Coordinator::Write::DecisionContexts::ResultV1.new(
      effective_decision:,
      shadowed_decisions: [],
      conflict:,
      unsupported_dimensions:,
      unsupported_decisions:,
      unresolved_decisions:
    )
  end

  def resolved_decision(
    decision_id:,
    option_id:,
    effect: "require",
    on_violation: "block",
    value_schema: "named-choice/v1",
    event_id: "0198e03a-d112-7000-8000-000000000001"
  )
    Coordinator::Write::DecisionContexts::ResolvedDecisionV1.new(
      head: decision_head(decision_id, event_id:),
      definition_digest: "sha256:#{'c' * 64}",
      topic_id: "testing.framework",
      effect:,
      modality: "must",
      value: {
        schema: value_schema,
        name: option_id,
        items: value_schema == "string-set/v1" ? [ "rspec" ] : nil,
        target_kind: nil,
        target_id: nil,
        action: nil
      },
      enforcement: {
        level: "implementation_gate",
        retroactivity: "active_attempts",
        on_violation:
      },
      anchor_kind: "repository",
      anchor_rank: 2,
      applicability_reasons: [ "topic_exact" ]
    )
  end

  def decision_head(decision_id, event_id: "0198e03a-d112-7000-8000-000000000001")
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id:,
      decision_revision: 1,
      event: {
        event_id:,
        type: "DecisionActivated",
        stream_context: "HumanGuidance",
        stream_name: "Decision",
        stream_id: decision_id,
        stream_revision: 1
      }
    )
  end
end
