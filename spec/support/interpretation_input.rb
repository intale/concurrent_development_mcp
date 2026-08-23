# frozen_string_literal: true

module InterpretationInput
  module_function

  def build(
    command_id: "cmd-interpretation-1",
    interpretation_id: "I-1",
    source_message_id: "M-1",
    source_span: { start_character: 4, end_character: 9, text: "RSpec" },
    statement_kind: "preference",
    topic_id: "testing.framework",
    effect: "prefer",
    modality: "should",
    value: named_choice("rspec"),
    scope: nil,
    conditions: default_conditions,
    validity: { valid_from: nil, valid_until: nil, until_event: nil },
    enforcement: advisory_enforcement,
    relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] },
    ambiguities: []
  )
    {
      command_id:,
      actor: { kind: "agent", id: "classifier-host" },
      interpretation_id:,
      source_message_id:,
      source_span:,
      classifier: {
        id: "classifier-a",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 940_000
      },
      proposed_decision: {
        statement_kind:,
        topic_id:,
        effect:,
        modality:,
        value:,
        scope:,
        conditions:,
        validity:,
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement:,
        relations:
      },
      ambiguities:
    }
  end

  def named_choice(name)
    {
      schema: "named-choice/v1",
      name:,
      items: nil,
      target_kind: nil,
      target_id: nil,
      action: nil
    }
  end

  def string_set(items)
    {
      schema: "string-set/v1",
      name: nil,
      items:,
      target_kind: nil,
      target_id: nil,
      action: nil
    }
  end

  def advisory_enforcement
    {
      level: "advisory",
      retroactivity: "future_only",
      on_violation: "warn"
    }
  end

  def impact_policy(
    level:,
    required_evidence: [ "combined_tests" ],
    change_set_id: "CS-1",
    **overrides
  )
    build(**impact_policy_attributes(level:, required_evidence:, change_set_id:).merge(overrides))
  end

  def impact_policy_attributes(level:, required_evidence: [ "combined_tests" ], change_set_id: "CS-1")
    {
      statement_kind: "directive",
      topic_id: "candidate.impact_policy",
      effect: "require",
      modality: "must",
      value: string_set(required_evidence),
      scope: scope(change_set_id:),
      conditions: empty_conditions,
      validity: { valid_from: nil, valid_until: nil, until_event: nil },
      enforcement: {
        level:,
        retroactivity: "all_unmerged_candidates",
        on_violation: %w[verification_gate merge_gate].include?(level) ? "block" : "warn"
      }
    }
  end

  def default_conditions
    {
      phases: [ "implementation" ],
      languages: [ "ruby" ],
      tags: [],
      repository_kinds: [],
      artifact_kinds: [],
      environments: []
    }
  end

  def empty_conditions
    {
      phases: [],
      languages: [],
      tags: [],
      repository_kinds: [],
      artifact_kinds: [],
      environments: []
    }
  end

  def adjudication(
    command_id: "cmd-adjudication-1",
    source_message_id: "M-1",
    interpretation_id: "I-1",
    action: "accept",
    rationale: { code: "user_confirmed", summary: "The proposed reading matches the intended guidance." },
    clarification: nil
  )
    {
      command_id:,
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id:,
      interpretation_id:,
      action:,
      rationale:,
      clarification:
    }
  end

  def clarification
    {
      status: "needs_classification",
      questions: [
        {
          field: "scope",
          prompt: "Which repository should this interpretation govern?",
          options: [ "billing", "orders" ]
        }
      ]
    }
  end

  def activation(
    command_id: "cmd-decision-activation-1",
    decision_id: "D-1",
    interpretation_id: "I-1",
    rationale: { code: "user_confirmed", summary: "Activate the accepted policy." }
  )
    {
      command_id:,
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id:,
      rationale:
    }
  end

  def correction(
    expected_head:,
    command_id: "cmd-decision-correction-1",
    decision_id: "D-1",
    interpretation_id: "I-2",
    rationale: { code: "normalization_corrected", summary: "Apply the accepted correction." }
  )
    {
      command_id:,
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id:,
      expected_head:,
      rationale:
    }
  end

  def scope(
    workspace_id: nil,
    repository_ids: [],
    change_set_id: nil,
    work_item_id: nil,
    attempt_id: nil,
    candidate_id: nil
  )
    {
      workspace_id:,
      repository_ids:,
      branch_selectors: [],
      change_set_id:,
      work_item_id:,
      attempt_id:,
      candidate_id:,
      path_selectors: [],
      symbol_selectors: [],
      contract_selectors: [],
      schema_selectors: [],
      environments: [],
      agent_roles: []
    }
  end
end
