# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionResolve, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::DecisionGovernanceV1.new }
  let(:input) do
    {
      topic_id: "testing.framework",
      context: {
        repository_id: "billing",
        change_set_id: "CS-resolve",
        work_item_id: "W-resolve",
        attempt_id: "A-resolve",
        phase: "implementation",
        language: "ruby",
        paths: %w[spec/z_spec.rb spec/a_spec.rb spec/z_spec.rb],
        agent_role: "implementer"
      }
    }
  end

  it "serves explicit absent and partial projections before converging on an effective Decision" do
    seed_active_decision
    recorded, activated = decision_events("D-resolve")
    partition = partition_events("repo:billing:testing").sole

    absent = query.call(input).value!
    expect(absent).to have_attributes(status: "ok")
    expect(absent.context_token).to match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    expect(absent.data.decision_context.document).to have_attributes(
      effective_decision: nil,
      conflict: nil
    )
    expect(absent.data.decision_context.document.query_context.paths).to eq(%w[spec/a_spec.rb spec/z_spec.rb])
    expect(absent.data.decision_context.document.partitions.map { _1.partition.partition_id }).to eq(
      %w[
        repo:billing:testing
        changeset:CS-resolve:testing
        workitem:W-resolve:testing
        attempt:A-resolve:testing
      ]
    )
    expect(absent.data.decision_context.document.partitions).to all(
      have_attributes(partition_revision: nil, event: nil, active_decisions: [])
    )

    projector.call(partition)
    partial = query.call(input).value!
    expect(partial).to have_attributes(status: "ok")
    expect(partial.data.decision_context.document.effective_decision).to be_nil
    expect(partial.warnings.sole).to start_with("decision_definition_not_observed:D-resolve:")
    expect(partial.data.decision_context.document.partitions.first).to have_attributes(
      partition_revision: 0,
      active_decisions: contain_exactly(have_attributes(decision_id: "D-resolve"))
    )

    projector.call(recorded)
    projector.call(activated)
    resolved = query.call(input).value!
    repeated = query.call(input).value!
    effective = resolved.data.decision_context.document.effective_decision
    expect(resolved).to have_attributes(status: "ok", warnings: [])
    expect(effective).to have_attributes(
      head: have_attributes(decision_id: "D-resolve", decision_revision: 1),
      topic_id: "testing.framework",
      anchor_kind: "repository",
      anchor_rank: 2
    )
    expect(effective.value.name).to eq("rspec")
    expect(resolved.context_token).to eq(resolved.data.decision_context.digest)
    expect(repeated.context_token).to eq(resolved.context_token)
    expect(repeated.data.decision_context.resolved_at).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(resolved.to_h.keys & %i[active fresh pending projection_status stream_revision]).to be_empty
  end

  it "returns an available same-rank conflict without inventing a winner" do
    seed_active_decision(
      decision_id: "D-A",
      interpretation_id: "I-A",
      message_id: "M-A",
      command_suffix: "a",
      scope: InterpretationInput.scope(repository_ids: [ "billing" ])
    )
    seed_active_decision(
      decision_id: "D-B",
      interpretation_id: "I-B",
      message_id: "M-B",
      command_suffix: "b",
      scope: InterpretationInput.scope(repository_ids: %w[billing orders]),
      value: InterpretationInput.named_choice("minitest")
    )
    %w[D-A D-B].each do |decision_id|
      decision_events(decision_id).each { projector.call(_1) }
    end
    partition_events("repo:billing:testing").each { projector.call(_1) }

    result = query.call(input).value!

    expect(result).to have_attributes(status: "conflict")
    expect(result.data.decision_context.document.effective_decision).to be_nil
    expect(result.data.decision_context.document.conflict).to have_attributes(
      reason: "tied_most_specific"
    )
    expect(result.data.decision_context.document.conflict.decisions.map { _1.head.decision_id }).to eq(%w[D-A D-B])
  end

  it "resolves a registered non-testing single-choice topic using its own partition root" do
    seed_active_decision(
      decision_id: "D-impact",
      interpretation_id: "I-impact",
      message_id: "M-impact",
      command_suffix: "impact",
      proposal: InterpretationInput.impact_policy(
        level: "advisory",
        change_set_id: "CS-resolve",
        command_id: "cmd-proposal-impact",
        interpretation_id: "I-impact",
        source_message_id: "M-impact"
      )
    )
    decision_events("D-impact").each { projector.call(_1) }
    partition_events("changeset:CS-resolve:candidate").each { projector.call(_1) }

    result = query.call(input.merge(topic_id: "candidate.impact_policy")).value!
    document = result.data.decision_context.document

    expect(result).to have_attributes(status: "ok")
    expect(document).to have_attributes(
      resolution_policy: "single-choice-resolution/v1",
      topic_id: "candidate.impact_policy"
    )
    expect(document.partitions.map { _1.partition.topic_root }).to all(eq("candidate"))
    expect(document.effective_decision).to have_attributes(
      head: have_attributes(decision_id: "D-impact"),
      topic_id: "candidate.impact_policy",
      anchor_kind: "change_set",
      anchor_rank: 3
    )
    expect(document.effective_decision.value.items).to eq([ "combined_tests" ])
  end

  it "returns typed unsupported strategy and unknown-topic results" do
    unsupported = query.call(input.merge(topic_id: "testing.required_suites")).value!
    unknown = query.call(input.merge(topic_id: "testing.unknown")).value!

    expect(unsupported).to have_attributes(status: "invalid")
    expect(unsupported.data).to have_attributes(code: "decision_resolution_strategy_not_supported")
    expect(unsupported.data.details).to include(
      topic_id: "testing.required_suites",
      resolution_strategy: "set_union"
    )
    expect(unknown).to have_attributes(status: "invalid")
    expect(unknown.data).to have_attributes(code: "decision_topic_not_supported")
  end

  it "freezes the canonical empty-context digest independently of observation time" do
    golden = input.merge(
      context: input.fetch(:context).merge(
        change_set_id: "CS-golden",
        work_item_id: "W-golden",
        attempt_id: "A-golden"
      )
    )

    expect(query.call(golden).value!.context_token).to eq(
      "sha256:29b7063e311213beb48a2d5aa4e1fa7f9d3a42f891c68f29d284615754b77c5a"
    )
  end

  def seed_active_decision(
    decision_id: "D-resolve",
    interpretation_id: "I-resolve",
    message_id: "M-resolve",
    command_suffix: "resolve",
    proposal: nil,
    **proposal_overrides
  )
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-#{command_suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-#{command_suffix}",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    proposal ||= InterpretationInput.build(
      command_id: "cmd-proposal-#{command_suffix}",
      interpretation_id:,
      source_message_id: message_id,
      **proposal_overrides
    )
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, proposal)
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "cmd-adjudication-#{command_suffix}",
      source_message_id: message_id,
      interpretation_id:
    ))
    execute(Coordinator::Write::Operations::ExecuteActivateDecision, InterpretationInput.activation(
      command_id: "cmd-activation-#{command_suffix}",
      decision_id:,
      interpretation_id:
    ))
  end

  def execute(operation_class, arguments)
    operation_class.new(event_store:).call(arguments).value!
  end

  def decision_events(decision_id)
    event_store.read(streams.decision(decision_id), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end

  def partition_events(partition_id)
    event_store.read(
      streams.decision_partition(partition_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 32,
        direction: :asc
      )
    )
  end
end
