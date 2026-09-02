# frozen_string_literal: true

RSpec.describe Coordinator::Write::Interpretations::InterpretationSlotBuilder do
  subject(:builder) { described_class.new }

  let(:proposal) do
    Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      interpretation_id: "I-1",
      source_message_id: "M-1",
      source_event: event_reference("000001"),
      source_span: nil,
      classifier: Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
        id: "classifier-a",
        version: "v1",
        ontology_version: 1,
        confidence_millionths: 900_000
      ),
      proposed_decision: proposed_decision([
        RepositoryScenario.repository_id("orders"),
        RepositoryScenario::DEFAULT_REPOSITORY_ID
      ]),
      scope_provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
        kind: "explicit",
        anchor_level: "repository",
        source_message_id: "M-1"
      ),
      ambiguities: [],
      assessment: Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(
        status: "accepted_for_activation",
        reasons: [],
        questions: []
      ),
      proposed_at: "2026-08-22T17:00:00.000000Z"
    )
  end

  def proposed_decision(repository_ids)
    Coordinator::Write::Interpretations::ProposedDecisionV1.new(
      statement_kind: "preference",
      topic_id: "testing.framework",
      effect: "prefer",
      modality: "should",
      value: Coordinator::Write::Interpretations::DecisionValueV1.new(
        schema: "named-choice/v1",
        name: "rspec",
        items: nil,
        target_kind: nil,
        target_id: nil,
        action: nil
      ),
      scope: Coordinator::Write::Interpretations::DecisionScopeV1.new(
        workspace_id: nil,
        repository_ids:,
        branch_selectors: %w[release main],
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
      ),
      conditions: Coordinator::Write::Interpretations::DecisionConditionsV1.new(
        phases: [], languages: [], tags: [], repository_kinds: [], artifact_kinds: [], environments: []
      ),
      validity: Coordinator::Write::Interpretations::DecisionValidityV1.new(
        valid_from: nil, valid_until: nil, until_event: nil
      ),
      authority: Coordinator::Write::Interpretations::DecisionAuthorityV1.new(
        actor_id: "user-label", role: "project-owner"
      ),
      enforcement: Coordinator::Write::Interpretations::DecisionEnforcementV1.new(
        level: "advisory", retroactivity: "future_only", on_violation: "warn"
      ),
      relations: Coordinator::Write::Interpretations::DecisionRelationsV1.new(
        corrects: [], supersedes: [], exception_to: [], revokes: []
      )
    )
  end

  def event_reference(suffix)
    Coordinator::Write::EventReference.new(
      event_id: "01900000-0000-7000-8000-000000#{suffix}",
      type: "UserUtteranceRecorded",
      stream_context: "HumanGuidance",
      stream_name: "Conversation",
      stream_id: "C-1",
      stream_revision: 0
    )
  end

  it "normalizes semantically identical exact scopes into one compound slot" do
    reordered = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      proposal.to_h.merge(
        proposed_decision: proposed_decision([
          RepositoryScenario::DEFAULT_REPOSITORY_ID,
          RepositoryScenario.repository_id("orders")
        ])
      )
    )

    first = builder.call(proposal)
    second = builder.call(reordered)

    expect(first.compound_marker.marker).to eq(second.compound_marker.marker)
    expect(first.document.exact_scope.repository_ids).to eq([
      RepositoryScenario::DEFAULT_REPOSITORY_ID,
      RepositoryScenario.repository_id("orders")
    ].sort)
    expect(first.compound_marker.components).to include(
      "message:M-1",
      "topic:testing.framework",
      "conflict-dimension:primary_test_framework",
      "resolution-strategy:single_choice"
    )
    scope_components = first.compound_marker.components.grep(/\Ascope-[0-9]{3}:/).sort
    encoded_scope = scope_components.map { _1.partition(":").last }.join
    expect(encoded_scope).to eq(Coordinator::Shared::CanonicalJson.new.encode(first.document.exact_scope.to_h))
  end

  it "keeps different messages and scopes in distinct slots" do
    another_message = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      proposal.to_h.merge(source_message_id: "M-2")
    )
    another_scope = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      proposal.to_h.merge(
        proposed_decision: proposed_decision([ RepositoryScenario.repository_id("catalog") ])
      )
    )

    markers = [ proposal, another_message, another_scope ].map { builder.call(_1).compound_marker.marker }

    expect(markers.uniq.length).to eq(3)
  end
end
