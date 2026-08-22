# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionGovernanceV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "projects recorded and active evidence idempotently without a freshness gate" do
    activation = activate_decision
    recorded, activated = decision_events("D-project")
    slot_events = slot_events(activation.data.slot.slot_id)
    partition = partition_events("repo:billing:testing").sole

    projector.call(recorded)
    projector.call(recorded)

    available = repository.fetch("D-project")
    expect(available).to have_attributes(
      decision_id: "D-project",
      interpretation_id: "I-project",
      policy_status: "recorded",
      activated: nil
    )
    expect(available.recorded.to_h).to include(
      event: include(event_id: recorded.id, type: "DecisionRecorded", stream_revision: 0),
      actor: include(kind: "orchestrator", id: "guidance-host", authenticated: false),
      causation_id: recorded.causation_id,
      correlation_id: recorded.correlation_id
    )

    [ activated, *slot_events, partition ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    projected = repository.fetch("D-project")
    expect(projected).to have_attributes(policy_status: "active")
    expect(projected.definition.document).to have_attributes(effect: "prefer", modality: "should")
    expect(projected.definition.document.topic.topic_id).to eq("testing.framework")
    expect(projected.slot.slot_id).to eq(activation.data.slot.slot_id)
    expect(projected.partitions.sole).to have_attributes(
      partition_id: "repo:billing:testing",
      anchor_kind: "repo",
      anchor_id: "billing"
    )
    expect(projected.activated.to_h).to include(
      event: include(event_id: activated.id, type: "DecisionActivated", stream_revision: 1),
      causation_id: activated.causation_id,
      correlation_id: activated.correlation_id
    )
    expect(Coordinator::Read::DecisionDefinition.count).to eq(1)
    expect(Coordinator::Read::DecisionSlotHead.find(activation.data.slot.slot_id)).to have_attributes(
      decision_id: "D-project"
    )
    expect(Coordinator::Read::DecisionPartitionHead.find("repo:billing:testing")).to have_attributes(
      decision_id: "D-project",
      partition_revision: 0,
      change_kind: "activated"
    )
    expect(processed_events.count).to eq(5)
  end

  it "retains the newest partition head when delivery order crosses decisions" do
    activate_decision(
      command_suffix: "a",
      decision_id: "D-A",
      interpretation_id: "I-A",
      message_id: "M-A",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec cucumber])
    )
    activate_decision(
      command_suffix: "b",
      decision_id: "D-B",
      interpretation_id: "I-B",
      message_id: "M-B",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec mutation])
    )
    partition_events = partition_events("repo:billing:testing")
    expect(partition_events.map(&:stream_revision)).to eq([ 0, 1 ])

    %w[D-A D-B].each do |decision_id|
      decision_events(decision_id).each { projector.call(_1) }
    end
    partition_events.reverse_each { projector.call(_1) }

    head = Coordinator::Read::DecisionPartitionHead.find("repo:billing:testing")
    expect(head).to have_attributes(decision_id: "D-B", partition_revision: 1, change_kind: "activated")
    expect(head.decision).to include("decision_id" => "D-B")
  end

  def activate_decision(
    command_suffix: "project",
    decision_id: "D-project",
    interpretation_id: "I-project",
    message_id: "M-project",
    **proposal_overrides
  )
    record_guidance(message_id:, command_suffix:)
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "cmd-proposal-#{command_suffix}",
      interpretation_id:,
      source_message_id: message_id,
      **proposal_overrides
    ))
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

  def record_guidance(message_id:, command_suffix:)
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
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def decision_events(decision_id)
    event_store.read(streams.decision(decision_id), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end

  def slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def partition_events(partition_id)
    event_store.read(
      streams.decision_partition(partition_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::DecisionGovernance.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "decision_governance",
      projection_version: 1
    )
  end
end
