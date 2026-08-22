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
    enforcement: advisory_enforcement,
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
        conditions: {
          phases: [ "implementation" ],
          languages: [ "ruby" ],
          tags: [],
          repository_kinds: [],
          artifact_kinds: [],
          environments: []
        },
        validity: { valid_from: nil, valid_until: nil, until_event: nil },
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement:,
        relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
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
end
