# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Interpretations::Propose do
  subject(:decider) { described_class.new }

  let(:preparer) { Coordinator::Write::Operations::PrepareProposeDecisionInterpretation.new }
  let(:proposed_at) { "2026-08-22T15:30:00.000000Z" }
  let(:source) do
    Coordinator::Write::Interpretations::GuidanceSourceEvidenceV1.new(
      message_id: "M-1",
      text: "Use RSpec.",
      anchors: Coordinator::Write::GuidanceAnchorsV1.new(
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      ),
      event: Coordinator::Write::EventReference.new(
        event_id: "01900000-0000-7000-8000-000000000001",
        type: "UserUtteranceRecorded",
        stream_context: "HumanGuidance",
        stream_name: "Conversation",
        stream_id: "C-1",
        stream_revision: 0
      )
    )
  end
  let(:input) do
    {
      command_id: "cmd-interpretation-1",
      actor: { kind: "agent", id: "classifier-host" },
      interpretation_id: "I-1",
      source_message_id: "M-1",
      source_span: { start_character: 4, end_character: 9, text: "RSpec" },
      classifier: {
        id: "classifier-a",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 940_000
      },
      proposed_decision: {
        statement_kind: "preference",
        topic_id: "testing.framework",
        effect: "prefer",
        modality: "should",
        value: {
          schema: "named-choice/v1",
          name: "rspec",
          items: nil,
          target_kind: nil,
          target_id: nil,
          action: nil
        },
        scope: nil,
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
        enforcement: {
          level: "advisory",
          retroactivity: "future_only",
          on_violation: "warn"
        },
        relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
      },
      ambiguities: []
    }
  end

  def command(attributes = input)
    preparer.call(attributes).value!
  end

  def state(source_value = source, proposal_exists: false)
    Coordinator::Write::Domain::Interpretations::State.new(
      source: source_value,
      proposal_exists:
    )
  end

  it "implements GDN-02-READY-01 with one non-normative proposal" do
    result = decider.call(state: state, command: command, proposed_at:)

    expect(result).to be_success
    proposal = result.value!.events.sole
    expect(proposal).to be_a(Coordinator::Write::Events::DecisionInterpretationProposedV1)
    expect(proposal.assessment.status).to eq("accepted_for_activation")
    expect(proposal.proposed_decision.scope).to have_attributes(
      repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
      work_item_id: "W-1"
    )
    expect(proposal.scope_provenance).to have_attributes(kind: "inferred", anchor_level: "work_item")
  end

  it "implements GDN-02-CONFIRM-01 with proposal and clarification from one command" do
    enforcement = input.dig(:proposed_decision, :enforcement).merge(
      level: "merge_gate",
      on_violation: "block"
    )
    decision = input.fetch(:proposed_decision).merge(
      effect: "forbid",
      modality: "must_not",
      enforcement:
    )

    result = decider.call(
      state: state,
      command: command(input.merge(proposed_decision: decision)),
      proposed_at:
    )

    expect(result.value!.events.map(&:class)).to eq([
      Coordinator::Write::Events::DecisionInterpretationProposedV1,
      Coordinator::Write::Events::DecisionClarificationRequiredV1
    ])
    expect(result.value!.events.first.assessment.status).to eq("confirmation_required")
  end

  it "implements GDN-02-UNCERTAIN-01 without coercing a question into policy" do
    decision = input.fetch(:proposed_decision).merge(statement_kind: "question", scope: nil)
    uncertain_source = Coordinator::Write::Interpretations::GuidanceSourceEvidenceV1.new(
      source.to_h.merge(
        anchors: Coordinator::Write::GuidanceAnchorsV1.new(
          repository_ids: [],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        )
      )
    )

    result = decider.call(
      state: state(uncertain_source),
      command: command(input.merge(proposed_decision: decision)),
      proposed_at:
    )

    expect(result.value!.events.first.assessment).to have_attributes(
      status: "needs_classification",
      reasons: include("non_normative_statement_kind", "scope_unresolved")
    )
    expect(result.value!.events.length).to eq(2)
  end

  it "requires classification for explicit empty scope and clears ambiguous inferred repositories" do
    empty_scope = {
      workspace_id: nil,
      repository_ids: [],
      branch_selectors: [],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil,
      candidate_id: nil,
      path_selectors: [],
      symbol_selectors: [],
      contract_selectors: [],
      schema_selectors: [],
      environments: [],
      agent_roles: []
    }
    explicit_decision = input.fetch(:proposed_decision).merge(scope: empty_scope)
    explicit = decider.call(
      state: state,
      command: command(input.merge(proposed_decision: explicit_decision)),
      proposed_at:
    ).value!.events.first
    ambiguous_source = Coordinator::Write::Interpretations::GuidanceSourceEvidenceV1.new(
      source.to_h.merge(
        anchors: Coordinator::Write::GuidanceAnchorsV1.new(
          repository_ids: [
            RepositoryScenario::DEFAULT_REPOSITORY_ID,
            RepositoryScenario.repository_id("orders")
          ],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        )
      )
    )
    inferred = decider.call(
      state: state(ambiguous_source),
      command: command,
      proposed_at:
    ).value!.events.first

    expect(explicit.scope_provenance).to have_attributes(
      kind: "explicit",
      anchor_level: "unresolved"
    )
    expect(explicit.assessment).to have_attributes(
      status: "needs_classification",
      reasons: include("scope_unresolved")
    )
    expect(inferred.scope_provenance).to have_attributes(
      kind: "unresolved",
      anchor_level: "unresolved"
    )
    expect(inferred.proposed_decision.scope.repository_ids).to be_empty
    expect(inferred.assessment.status).to eq("needs_classification")
  end

  it "denies missing source, mismatched span, unsupported topic, bad topic value, and reused identity" do
    missing = decider.call(state: state(nil), command: command, proposed_at:)
    mismatch = decider.call(
      state: state,
      command: command(input.merge(source_span: { start_character: 0, end_character: 3, text: "bad" })),
      proposed_at:
    )
    unsupported_decision = input.fetch(:proposed_decision).merge(topic_id: "architecture.unknown")
    unsupported = decider.call(
      state: state,
      command: command(input.merge(proposed_decision: unsupported_decision)),
      proposed_at:
    )
    bad_value = input.dig(:proposed_decision, :value).merge(
      schema: "string-set/v1",
      name: nil,
      items: [ "rspec" ]
    )
    bad_decision = input.fetch(:proposed_decision).merge(value: bad_value)
    invalid_value = decider.call(
      state: state,
      command: command(input.merge(proposed_decision: bad_decision)),
      proposed_at:
    )
    duplicate = decider.call(state: state(source, proposal_exists: true), command: command, proposed_at:)

    expect([ missing, mismatch, unsupported, invalid_value, duplicate ].map { _1.failure.code }).to eq(%i[
      guidance_message_not_found
      source_span_mismatch
      topic_not_supported
      topic_value_invalid
      interpretation_already_proposed
    ])
  end

  it "defends the Candidate impact policy invariant when a typed command bypasses public preparation" do
    valid = command(InterpretationInput.impact_policy(level: "verification_gate"))
    invalid_enforcement = Coordinator::Write::Interpretations::DecisionEnforcementV1.new(
      valid.proposed_decision.enforcement.to_h.merge(on_violation: "warn")
    )
    invalid_decision = Coordinator::Write::Interpretations::SubmittedDecisionV1.new(
      valid.proposed_decision.to_h.merge(enforcement: invalid_enforcement)
    )
    invalid_command = Coordinator::Write::Commands::ProposeDecisionInterpretation.new(
      valid.to_h.merge(proposed_decision: invalid_decision)
    )

    result = decider.call(state: state, command: invalid_command, proposed_at:)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(code: :topic_value_invalid)
  end
end
