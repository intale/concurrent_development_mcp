# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::ProposeDecisionInterpretation do
  subject(:contract) { described_class.new }

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

  it "accepts one strict atomic interpretation document" do
    expect(contract.call(input)).to be_success
  end

  it "rejects an anonymous multi-proposal shape" do
    result = contract.call(input.merge(proposals: [ input.fetch(:proposed_decision) ]))

    expect(result).to be_failure
    expect(result.errors.to_h).to have_key(:proposals)
  end

  it "rejects value fields outside the selected strict schema" do
    value = input.dig(:proposed_decision, :value).merge(items: [ "rspec" ])
    decision = input.fetch(:proposed_decision).merge(value:)

    result = contract.call(input.merge(proposed_decision: decision))

    expect(result).to be_failure
    expect(result.errors.to_h.dig(:proposed_decision, :value)).to include(:items)
  end

  it "rejects an invalid validity interval and duplicate selectors" do
    scope = {
      workspace_id: nil,
      repository_ids: %w[billing billing],
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
    decision = input.fetch(:proposed_decision).merge(
      scope:,
      validity: {
        valid_from: "2026-08-22T10:00:00.000000Z",
        valid_until: "2026-08-22T09:00:00.000000Z",
        until_event: nil
      }
    )

    result = contract.call(input.merge(proposed_decision: decision))

    expect(result).to be_failure
    expect(result.errors.to_h.dig(:proposed_decision, :scope)).to have_key(:repository_ids)
    expect(result.errors.to_h.dig(:proposed_decision, :validity)).to have_key(:valid_until)
  end
end
