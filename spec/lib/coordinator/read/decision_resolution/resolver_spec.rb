# frozen_string_literal: true

RSpec.describe Coordinator::Read::DecisionResolution::Resolver do
  subject(:resolver) { described_class.new }

  let(:context) do
    Coordinator::Read::DecisionResolution::QueryContextV1.new(
      workspace_id: "workspace-1",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    )
  end
  let(:resolved_at) { "2026-08-22T12:00:00.000000Z" }

  it "selects the unique most-specific applicable Decision and shadows broader evidence" do
    repository = decision(
      decision_id: "D-repository",
      sequence: 1,
      scope: scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ]),
      value: "rspec"
    )
    attempt = decision(
      decision_id: "D-attempt",
      sequence: 2,
      scope: scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ], attempt_id: "A-1"),
      value: "minitest"
    )
    observations = [
      observation("repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing", "repo", "billing", [ head(repository) ], sequence: 11),
      observation("attempt:A-1:testing", "attempt", "A-1", [ head(attempt) ], sequence: 12)
    ]

    result = resolver.call(
      topic_id: "testing.framework",
      context:,
      observations:,
      decisions: [ repository, attempt ],
      resolved_at:
    )

    expect(result.effective_decision).to have_attributes(
      head: have_attributes(decision_id: "D-attempt"),
      anchor_kind: "attempt",
      anchor_rank: 5
    )
    expect(result.shadowed_decisions).to contain_exactly(
      have_attributes(
        reason: "less_specific",
        decision: have_attributes(head: have_attributes(decision_id: "D-repository"))
      )
    )
    expect(result.conflict).to be_nil
  end

  it "preserves a same-rank tie as an explicit conflict" do
    narrow_set = decision(
      decision_id: "D-A",
      sequence: 3,
      scope: scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ]),
      value: "rspec"
    )
    broad_set = decision(
      decision_id: "D-B",
      sequence: 4,
      scope: scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID, RepositoryScenario.repository_id("orders") ]),
      value: "minitest"
    )
    observation = observation(
      "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing",
      "repo",
      "billing",
      [ head(narrow_set), head(broad_set) ],
      sequence: 13
    )

    result = resolver.call(
      topic_id: "testing.framework",
      context:,
      observations: [ observation ],
      decisions: [ broad_set, narrow_set ],
      resolved_at:
    )

    expect(result.effective_decision).to be_nil
    expect(result.conflict).to have_attributes(reason: "tied_most_specific")
    expect(result.conflict.decisions.map { _1.head.decision_id }).to eq(%w[D-A D-B])
  end

  it "reports unsupported dimensions and unresolved projected heads without guessing" do
    unsupported = decision(
      decision_id: "D-unsupported",
      sequence: 5,
      scope: scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ]).merge(branch_selectors: [ "main" ]),
      value: "rspec"
    )
    missing = Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: "D-missing",
      decision_revision: 1,
      event: reference("D-missing", "Decision", "DecisionActivated", 1, 6)
    )
    observation = observation(
      "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing",
      "repo",
      "billing",
      [ head(unsupported), missing ],
      sequence: 14
    )

    result = resolver.call(
      topic_id: "testing.framework",
      context:,
      observations: [ observation ],
      decisions: [ unsupported ],
      resolved_at:
    )

    expect(result.unsupported_dimensions).to eq([ "scope.branch_selectors" ])
    expect(result.unsupported_decisions.map(&:decision_id)).to eq([ "D-unsupported" ])
    expect(result.unresolved_decisions.map(&:decision_id)).to eq([ "D-missing" ])
    expect(result.effective_decision).to be_nil
  end

  def decision(decision_id:, sequence:, scope:, value:)
    definition = definition(scope:, value:)
    current_reference = reference(decision_id, "Decision", "DecisionActivated", 1, sequence)
    current_evidence = evidence(current_reference)
    recorded_reference = reference(decision_id, "Decision", "DecisionRecorded", 0, sequence + 100)

    Coordinator::Read::DecisionViewV1.new(
      decision_id:,
      interpretation_id: "I-#{decision_id}",
      source_message_id: "M-#{decision_id}",
      policy_status: "active",
      definition:,
      slot: nil,
      partitions: [],
      classifier: {
        id: "classifier",
        version: "classifier-v1",
        ontology_version: 1,
        confidence_millionths: 900_000
      },
      scope_provenance: {
        kind: "explicit",
        anchor_level: "repository",
        source_message_id: "M-#{decision_id}"
      },
      source_event: recorded_reference,
      proposal_event: recorded_reference,
      acceptance_event: recorded_reference,
      rationale: nil,
      correction_rationale: nil,
      previous_definition_digest: nil,
      correction_count: 0,
      recorded: evidence(recorded_reference),
      activated: current_evidence,
      corrected: nil,
      current_head: current_evidence
    )
  end

  def definition(scope:, value:)
    document = Coordinator::Write::Decisions::DecisionDefinitionDocumentV1.new(
      schema: "decision-definition/v1",
      statement_kind: "preference",
      topic: Coordinator::Write::Interpretations::TopicRegistry.new.fetch("testing.framework"),
      effect: "prefer",
      modality: "should",
      value: InterpretationInput.named_choice(value),
      scope:,
      conditions: {
        phases: [ "implementation" ],
        languages: [ "ruby" ],
        tags: [],
        repository_kinds: [],
        artifact_kinds: [],
        environments: [ "test" ]
      },
      validity: {
        valid_from: "2026-01-01T00:00:00.000000Z",
        valid_until: "2027-01-01T00:00:00.000000Z",
        until_event: nil
      },
      authority: { actor_id: "user-label", role: "project-owner" },
      enforcement: InterpretationInput.advisory_enforcement,
      relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
    )
    Coordinator::Write::Decisions::DecisionDefinitionV1.new(
      document:,
      digest: Coordinator::Shared::CanonicalJson.new.sha256(document.to_h)
    )
  end

  def scope(**overrides)
    InterpretationInput.scope(workspace_id: "workspace-1", **overrides).merge(
      path_selectors: [ "spec/models/order_spec.rb" ],
      environments: [ "test" ],
      agent_roles: [ "implementer" ]
    )
  end

  def head(decision)
    event = decision.current_head.event
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: decision.decision_id,
      decision_revision: event.stream_revision,
      event:
    )
  end

  def observation(partition_id, anchor_kind, anchor_id, active_decisions, sequence:)
    Coordinator::Read::DecisionResolution::PartitionObservationV1.new(
      partition: {
        partition_id:,
        topic_root: "testing",
        anchor_kind:,
        anchor_id:
      },
      partition_revision: 0,
      event: reference(partition_id, "DecisionPartition", "DecisionPartitionAdvanced", 0, sequence),
      active_decisions:
    )
  end

  def evidence(event)
    Coordinator::Read::DecisionLifecycleEvidenceV1.new(
      event:,
      actor: { kind: "user", id: "user-label", authenticated: false },
      occurred_at: resolved_at,
      persisted_at: resolved_at,
      causation_id: nil,
      correlation_id: nil
    )
  end

  def reference(stream_id, stream_name, type, stream_revision, sequence)
    Coordinator::Write::EventReference.new(
      event_id: format("0198e03a-d112-7%03x-8000-%012x", sequence, sequence),
      type:,
      stream_context: "HumanGuidance",
      stream_name:,
      stream_id:,
      stream_revision:
    )
  end
end
