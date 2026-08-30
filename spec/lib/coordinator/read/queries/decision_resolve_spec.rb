# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionResolve, :read_model do
  subject(:query) { described_class.new }

  DECISION_RESOLVE_REPOSITORY_ID = "0198f5b8-57ab-7def-8abc-1234567890ab"

  let(:input) do
    {
      topic_id: "testing.framework",
      context: {
        repository_id: DECISION_RESOLVE_REPOSITORY_ID,
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

  it "serves explicit absent and unresolved projections" do
    absent = query.call(input).value!
    expect(absent).to have_attributes(status: "ok")
    expect(absent.context_token).to match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    expect(absent.data.decision_context.document).to have_attributes(
      effective_decision: nil,
      conflict: nil
    )
    expect(absent.data.decision_context.document.query_context.paths).to eq(%w[spec/a_spec.rb spec/z_spec.rb])
    expect(absent.data.decision_context.document.partitions.map { _1.partition.partition_id }).to eq(
      %W[
        repo:#{DECISION_RESOLVE_REPOSITORY_ID}:testing
        changeset:CS-resolve:testing
        workitem:W-resolve:testing
        attempt:A-resolve:testing
      ]
    )

    create_partition_head(
      partition_id: "repo:#{DECISION_RESOLVE_REPOSITORY_ID}:testing",
      decision_id: "D-unobserved",
      event: decision_event("D-unobserved")
    )
    partial = query.call(input).value!

    expect(partial.data.decision_context.document.effective_decision).to be_nil
    expect(partial.warnings.sole).to start_with("decision_definition_not_observed:D-unobserved:")
  end

  it "resolves a coherent projected Decision and keeps the canonical context stable" do
    decision = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-resolve",
      repository_id: DECISION_RESOLVE_REPOSITORY_ID
    )
    create_partition_head(
      partition_id: "repo:#{DECISION_RESOLVE_REPOSITORY_ID}:testing",
      decision_id: decision.decision_id,
      event: decision.activated_event
    )

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
    expect(resolved.to_h.keys & %i[active fresh pending projection_status stream_revision]).to be_empty
  end

  it "returns an available same-rank conflict without inventing a winner" do
    first = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-A",
      repository_id: DECISION_RESOLVE_REPOSITORY_ID
    )
    second = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-B",
      repository_id: DECISION_RESOLVE_REPOSITORY_ID,
      definition_digest: "sha256:#{'f' * 64}"
    )
    heads = [ first, second ].map do |decision|
      decision_head(decision.decision_id, decision.activated_event)
    end
    create_partition_head(
      partition_id: "repo:#{DECISION_RESOLVE_REPOSITORY_ID}:testing",
      decision_id: first.decision_id,
      event: first.activated_event,
      active_decisions: heads
    )

    result = query.call(input).value!

    expect(result).to have_attributes(status: "conflict")
    expect(result.data.decision_context.document.effective_decision).to be_nil
    expect(result.data.decision_context.document.conflict).to have_attributes(
      reason: "tied_most_specific"
    )
    expect(result.data.decision_context.document.conflict.decisions.map { _1.head.decision_id }).to eq(%w[D-A D-B])
  end

  it "resolves a registered non-testing single-choice topic using its own partition root" do
    decision = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-impact",
      topic_id: "candidate.impact_policy",
      change_set_id: "CS-resolve",
      enforcement_level: "advisory"
    )
    create_partition_head(
      partition_id: "changeset:CS-resolve:candidate",
      decision_id: decision.decision_id,
      event: decision.activated_event,
      topic_root: "candidate",
      anchor_kind: "changeset",
      anchor_id: "CS-resolve"
    )

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
      "sha256:02f73fdd77fbcbf1446402e05a370b93f4fe1bd76a090fe155b3323b42a25fb9"
    )
  end

  def create_partition_head(
    partition_id:,
    decision_id:,
    event:,
    active_decisions: [ decision_head(decision_id, event) ],
    topic_root: "testing",
    anchor_kind: "repo",
    anchor_id: DECISION_RESOLVE_REPOSITORY_ID
  )
    create(
      :coordinator_read_decision_partition_head,
      partition_id:,
      decision_id:,
      partition: {
        "partition_id" => partition_id,
        "topic_root" => topic_root,
        "anchor_kind" => anchor_kind,
        "anchor_id" => anchor_id
      },
      decision: decision_head(decision_id, event),
      active_decisions:
    )
  end

  def decision_head(decision_id, event)
    { "decision_id" => decision_id, "decision_revision" => 1, "event" => event }
  end

  def decision_event(decision_id)
    {
      "event_id" => SecureRandom.uuid_v7,
      "type" => "DecisionActivated",
      "stream_context" => "HumanGuidance",
      "stream_name" => "Decision",
      "stream_id" => decision_id,
      "stream_revision" => 1
    }
  end
end
