# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::AgentChoiceImpacts::Assess do
  subject(:decider) { described_class.new }

  it "CHO-02-ASSESS-STILL-VALID-01 records one allowed assessment" do
    plan = assess(before_status: "allowed", after_status: "allowed")

    expect(plan.events.first).to have_attributes(
      class: Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1,
      assessment: have_attributes(
        outcome: "still_valid",
        reason: "compliant_or_advisory"
      )
    )
    expect(plan.events.drop(1).map(&:role)).to eq(%w[accepted_choice decision_change])
  end

  it "records prior noncompliance without blaming the later change" do
    plan = assess(before_status: "blocked", after_status: "blocked")

    expect(plan.events.first.assessment).to have_attributes(
      outcome: "still_valid",
      reason: "noncompliance_preceded_change"
    )
  end

  it "CHO-02-ASSESS-NOT-APPLICABLE-01 records a source already observed by the Choice" do
    plan = assess(
      before_status: "allowed",
      after_status: "blocked",
      source_already_observed: true
    )

    expect(plan.events.first.assessment).to have_attributes(
      outcome: "not_applicable",
      reason: "change_already_observed"
    )
  end

  it "records an inactive Attempt as not applicable" do
    plan = assess(
      before_status: "allowed",
      after_status: "blocked",
      active_attempt: false
    )

    expect(plan.events.first.assessment).to have_attributes(
      outcome: "not_applicable",
      reason: "attempt_not_active"
    )
  end

  it "CHO-02-ASSESS-ALREADY-INVALID-01 preserves the first terminal Choice fact" do
    plan = assess(
      before_status: "allowed",
      after_status: "blocked",
      invalidated: true
    )

    expect(plan.events.first.assessment).to have_attributes(
      outcome: "already_invalidated",
      reason: "choice_terminal"
    )
  end

  {
    "blocked" => "blocking_policy_introduced",
    "confirmation_required" => "confirmation_policy_introduced",
    "conflict" => "decision_conflict_introduced",
    "unsupported" => "unsupported_policy_introduced",
    "unresolved" => "unresolved_policy_introduced"
  }.each do |status, reason|
    it "CHO-02-ASSESS-INVALIDATE-01 atomically invalidates when the new evaluation is #{status}" do
      plan = assess(before_status: "allowed", after_status: status)

      expect(plan.events.map(&:class)).to eq(
        [
          Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1,
          Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1,
          Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1,
          Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV2
        ]
      )
      expect(plan.events.first.assessment).to have_attributes(
        outcome: "invalidated",
        reason:
      )
      expect(plan.events.last).to have_attributes(choice_id: "CHO-assess", reason:)
    end
  end

  def assess(
    before_status:,
    after_status:,
    source_already_observed: false,
    active_attempt: true,
    invalidated: false
  )
    decider.call(
      state: state(
        before_status:,
        after_status:,
        source_already_observed:,
        active_attempt:,
        invalidated:
      ),
      command:
    ).value!
  end

  def state(before_status:, after_status:, source_already_observed:, active_attempt:, invalidated:)
    Coordinator::Write::Domain::AgentChoiceImpacts::AssessmentState.new(
      choice: choice_snapshot(invalidated:),
      attempt: active_attempt ? active_attempt_state : Coordinator::Write::Domain::Attempts::State.initial,
      reconstruction: Coordinator::Write::AgentChoiceImpacts::ReconstructionV1.new(
        before_context: impact_context("b"),
        after_context: impact_context("a"),
        before_evaluation: evaluation(before_status),
        after_evaluation: evaluation(after_status),
        source_advancements: [ source_advancement ],
        source_already_observed:
      )
    )
  end

  def choice_snapshot(invalidated:)
    recorded = Coordinator::Write::Events::AgentChoiceRecordedV1.new(
      choice_id: "CHO-assess",
      choice_type: "testing.framework",
      selected: { option_id: "rspec", summary: "RSpec" },
      alternatives: [ { option_id: "minitest", summary: "Minitest" } ],
      reason_summary: "Follow the exact testing framework policy.",
      context: query_context,
      decision_context: recorded_context,
      recorded_at: "2026-08-23T10:00:00.000000Z"
    )
    accepted = Coordinator::Write::Events::AgentChoiceAcceptedV1.new(
      choice_id: "CHO-assess",
      recorded_event: recorded_reference,
      context_digest: recorded_context.digest,
      assessment: {
        basis: "no_policy",
        based_on_decisions: [],
        warnings: []
      },
      accepted_at: "2026-08-23T10:00:00.000000Z"
    )
    invalidation =
      if invalidated
        Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV1.new(
          choice_id: "CHO-assess",
          accepted_choice: accepted_reference,
          assessment_event: assessment_reference,
          decision_change_event: decision_change.source_event,
          previous_context_digest: "sha256:#{'b' * 64}",
          resulting_context_digest: "sha256:#{'a' * 64}",
          reason: "blocking_policy_introduced",
          invalidated_at: "2026-08-23T10:30:00.000000Z"
        )
      end
    Coordinator::Write::AgentChoiceImpacts::ChoiceSnapshotV1.new(
      choice_id: "CHO-assess",
      recorded:,
      recorded_event: recorded_reference,
      accepted:,
      accepted_event: accepted_reference,
      invalidation:,
      invalidation_event: invalidation && invalidation_reference
    )
  end

  def active_attempt_state
    Coordinator::Write::Domain::Attempts::State.new(
      attempt_id: "A-assess",
      change_set_id: "CS-assess",
      work_item_id: "W-assess",
      agent_id: "agent-a",
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          object_format: "sha1",
          commit_oid: "a" * 40
        )
      ],
      lease_set_id: nil,
      lease_repository_id: nil,
      lease_policy_version: nil,
      lease_resources: [],
      lease_reserved_at: nil,
      lease_renewed_at: nil,
      lease_expires_at: nil,
      lease_released_at: nil,
      status: "active"
    )
  end

  def evaluation(status)
    attributes = {
      "allowed" => [ "compliant", "selected_option_satisfies_decision" ],
      "blocked" => [ "blocking_violation", "selected_option_violates_blocking_decision" ],
      "confirmation_required" => [ "confirmation_required", "selected_option_requires_confirmation" ],
      "conflict" => [ "decision_conflict", "tied_most_specific_decisions" ],
      "unsupported" => [ "unsupported_context", "unsupported_decision_context" ],
      "unresolved" => [ "unresolved_head", "unresolved_decision_head" ]
    }.fetch(status)
    Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
      status:,
      effective_decision: status == "conflict" ? nil : decision_head,
      contributing_decisions: [ decision_head ],
      basis: attributes.fetch(0),
      warnings: [],
      reason_codes: [ attributes.fetch(1) ]
    )
  end

  def command
    Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
      command_id: "choice-impact-v1:#{'c' * 64}",
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      assessment_id: "0198e03a-d112-7000-8000-000000000013",
      choice_id: "CHO-assess",
      accepted_choice: accepted_reference,
      decision_change:,
      policy_version: "agent-choice-decision-impact/v1"
    )
  end

  def decision_change
    Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.new(
      source_event: decision_source_reference,
      source_global_position: 42,
      source_command_id: "cmd-correct-assess",
      source_actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id: "D-assess",
      change_kind: "corrected",
      definition_digest: "sha256:#{'d' * 64}",
      retroactivity: "active_attempts",
      affected_partitions: [ partition ],
      changed_at: "2026-08-23T10:30:00.000000Z"
    )
  end

  def recorded_context
    @recorded_context ||= begin
      observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context).map do |selected|
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition: selected,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
      resolution = Coordinator::Write::DecisionContexts::ResultV1.new(
        effective_decision: nil,
        shadowed_decisions: [],
        conflict: nil,
        unsupported_dimensions: [],
        unsupported_decisions: [],
        unresolved_decisions: []
      )
      Coordinator::Write::DecisionContexts::Builder.new.call(
        context: query_context,
        observations:,
        resolution:,
        resolved_at: "2026-08-23T10:00:00.000000Z"
      )
    end
  end

  def impact_context(digest_character)
    Coordinator::Write::DecisionContexts::ContextV1.new(
      document: recorded_context.document,
      digest: "sha256:#{digest_character * 64}",
      resolved_at: "2026-08-23T10:30:00.000000Z"
    )
  end

  def query_context
    Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      change_set_id: "CS-assess",
      work_item_id: "W-assess",
      attempt_id: "A-assess",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    )
  end

  def partition
    Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing",
      topic_root: "testing",
      anchor_kind: "repo",
      anchor_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
    )
  end

  def decision_head
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: "D-assess",
      decision_revision: 2,
      event: decision_source_reference
    )
  end

  def recorded_reference
    event_reference(
      event_id: "0198e03a-d112-7000-8000-000000000010",
      type: "AgentChoiceRecorded",
      stream_name: "AgentChoice",
      stream_id: "CHO-assess",
      stream_revision: 0
    )
  end

  def accepted_reference
    event_reference(
      event_id: "0198e03a-d112-7000-8000-000000000011",
      type: "AgentChoiceAccepted",
      stream_name: "AgentChoice",
      stream_id: "CHO-assess",
      stream_revision: 1
    )
  end

  def invalidation_reference
    event_reference(
      event_id: "0198e03a-d112-7000-8000-000000000012",
      type: "AgentChoiceInvalidatedByDecision",
      stream_name: "AgentChoice",
      stream_id: "CHO-assess",
      stream_revision: 2
    )
  end

  def assessment_reference
    event_reference(
      event_id: "0198e03a-d112-7000-8000-000000000013",
      type: "AgentChoiceImpactAssessed",
      stream_name: "AgentChoiceImpact",
      stream_id: "0198e03a-d112-7000-8000-000000000013",
      stream_revision: 0
    )
  end

  def decision_source_reference
    Coordinator::Write::EventReference.new(
      event_id: "0198e03a-d112-7000-8000-000000000014",
      type: "DecisionDefinitionCorrected",
      stream_context: "HumanGuidance",
      stream_name: "Decision",
      stream_id: "D-assess",
      stream_revision: 2
    )
  end

  def source_advancement
    Coordinator::Write::EventReference.new(
      event_id: "0198e03a-d112-7000-8000-000000000015",
      type: "DecisionPartitionAdvanced",
      stream_context: "HumanGuidance",
      stream_name: "DecisionPartition",
      stream_id: "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing",
      stream_revision: 1
    )
  end

  def event_reference(event_id:, type:, stream_name:, stream_id:, stream_revision:)
    Coordinator::Write::EventReference.new(
      event_id:,
      type:,
      stream_context: "AgentGovernance",
      stream_name:,
      stream_id:,
      stream_revision:
    )
  end
end
