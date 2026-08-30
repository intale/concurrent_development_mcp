# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionGovernanceV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects recorded and active evidence idempotently without a freshness gate" do
    lifecycle = activation_lifecycle
    recorded = lifecycle.fetch(:recorded)
    activated = lifecycle.fetch(:activated)

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

    [ activated, *lifecycle.fetch(:slot_events), lifecycle.fetch(:partition_event) ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    projected = repository.fetch("D-project")
    slot = lifecycle.fetch(:slot)
    partition_id = "repo:#{repository_id}:testing"
    expect(projected).to have_attributes(policy_status: "active")
    expect(projected.definition.document).to have_attributes(effect: "prefer", modality: "should")
    expect(projected.definition.document.topic.topic_id).to eq("testing.framework")
    expect(projected.slot.slot_id).to eq(slot.slot_id)
    expect(projected.partitions.sole).to have_attributes(
      partition_id:,
      anchor_kind: "repo",
      anchor_id: repository_id
    )
    expect(projected.activated.to_h).to include(
      event: include(event_id: activated.id, type: "DecisionActivated", stream_revision: 1),
      causation_id: activated.causation_id,
      correlation_id: activated.correlation_id
    )
    expect(Coordinator::Read::DecisionDefinition.count).to eq(1)
    expect(Coordinator::Read::DecisionSlotHead.find(slot.slot_id)).to have_attributes(
      decision_id: "D-project"
    )
    partition_head = Coordinator::Read::DecisionPartitionHead.find(partition_id)
    expect(partition_head).to have_attributes(
      decision_id: "D-project",
      partition_revision: 0,
      change_kind: "activated"
    )
    expect(partition_head.active_decisions).to contain_exactly(
      include("decision_id" => "D-project", "decision_revision" => 1)
    )
    expect(processed_events.count).to eq(5)
  end

  it "retains the newest partition head when delivery order crosses decisions" do
    first = activation_lifecycle(
      decision_id: "D-A",
      interpretation_id: "I-A",
      message_id: "M-A",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec cucumber]),
      position_offset: 0
    )
    second = activation_lifecycle(
      decision_id: "D-B",
      interpretation_id: "I-B",
      message_id: "M-B",
      topic_id: "testing.required_suites",
      effect: "require",
      modality: "must",
      value: InterpretationInput.string_set(%w[rspec mutation]),
      position_offset: 1_000,
      partition_revision: 1,
      previous_heads: [ first.fetch(:head) ]
    )

    [ first, second ].each do |lifecycle|
      projector.call(lifecycle.fetch(:recorded))
      projector.call(lifecycle.fetch(:activated))
    end
    [ second.fetch(:partition_event), first.fetch(:partition_event) ].each { projector.call(_1) }

    head = Coordinator::Read::DecisionPartitionHead.find("repo:#{repository_id}:testing")
    expect(head).to have_attributes(decision_id: "D-B", partition_revision: 1, change_kind: "activated")
    expect(head.decision).to include("decision_id" => "D-B")
    expect(head.active_decisions.map { _1.fetch("decision_id") }).to eq(%w[D-A D-B])
  end

  it "projects a corrected definition and vacated/moved slot without withholding the older view" do
    initial = activation_lifecycle
    [
      initial.fetch(:recorded),
      initial.fetch(:activated),
      *initial.fetch(:slot_events),
      initial.fetch(:partition_event)
    ].each { projector.call(_1) }

    stale_available = repository.fetch("D-project")
    expect(stale_available).to have_attributes(
      interpretation_id: "I-project",
      correction_count: 0,
      corrected: nil,
      current_head: have_attributes(event: have_attributes(event_id: initial.fetch(:activated).id))
    )

    corrected_definition = decision_definition(
      interpretation_id: "I-correction",
      message_id: "M-correction",
      value: InterpretationInput.named_choice("minitest"),
      scope: InterpretationInput.scope(repository_ids: [ repository_id ], work_item_id: "W-42"),
      relations: { corrects: [ "D-project" ], supersedes: [], exception_to: [], revokes: [] }
    )
    new_slot = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(corrected_definition)
    new_partitions = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(corrected_definition)
    correction_payload = Coordinator::Write::Events::DecisionDefinitionCorrectedV1.new(
      decision_id: "D-project",
      interpretation_id: "I-correction",
      source_message_id: "M-correction",
      source_event: source_reference("UserUtteranceRecorded", "Conversation", "C-correction", 0),
      proposal_event: source_reference("DecisionInterpretationProposed", "Interpretation", "M-correction", 0),
      acceptance_event: source_reference("DecisionInterpretationAccepted", "Interpretation", "M-correction", 1),
      previous_head: initial.fetch(:head),
      previous_definition_digest: initial.fetch(:definition).digest,
      definition: corrected_definition,
      classifier: classifier,
      scope_provenance: scope_provenance("M-correction", "work_item"),
      previous_slot: initial.fetch(:slot),
      slot: new_slot,
      previous_partitions: initial.fetch(:partitions),
      partitions: new_partitions,
      rationale: Coordinator::Write::Decisions::DecisionCorrectionRationaleV1.new(
        code: "normalization_corrected",
        summary: "Apply the accepted correction."
      ),
      corrected_at: "2026-08-30T12:10:00.000000Z"
    )
    correction = decision_stream_event(
      correction_payload,
      decision_id: "D-project",
      revision: 2,
      position: 2_000
    )
    corrected_head = decision_head("D-project", 2, correction)

    projector.call(correction)
    projector.call(correction)
    corrected = repository.fetch("D-project")
    expect(corrected).to have_attributes(
      interpretation_id: "I-correction",
      source_message_id: "M-correction",
      policy_status: "active",
      previous_definition_digest: stale_available.definition.digest,
      correction_count: 1
    )
    expect(corrected.definition.document.value.name).to eq("minitest")
    expect(corrected.definition.document.scope.work_item_id).to eq("W-42")
    expect(corrected.correction_rationale).to have_attributes(code: "normalization_corrected")
    expect(corrected.corrected.to_h).to include(
      event: include(event_id: correction.id, type: "DecisionDefinitionCorrected", stream_revision: 2),
      causation_id: correction.causation_id,
      correlation_id: correction.correlation_id
    )
    expect(corrected.current_head).to eq(corrected.corrected)

    old_slot = initial.fetch(:slot)
    slot_changes = [
      slot_head_event(old_slot.slot_id, initial.fetch(:head), nil, revision: 2, position: 2_100),
      *slot_lifecycle(new_slot, corrected_head, position_offset: 2_200)
    ]
    old_partition = initial.fetch(:partitions).sole
    new_partition = new_partitions.sole
    partition_changes = [
      partition_event(
        old_partition,
        corrected_head,
        active_heads: [],
        revision: 1,
        position: 2_400,
        change_kind: "corrected"
      ),
      partition_event(
        new_partition,
        corrected_head,
        active_heads: [ corrected_head ],
        revision: 0,
        position: 2_500,
        change_kind: "corrected"
      )
    ]
    [ *slot_changes, *partition_changes ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    expect(Coordinator::Read::DecisionSlotHead.find(old_slot.slot_id)).to have_attributes(
      decision_id: nil,
      head: nil
    )
    expect(Coordinator::Read::DecisionSlotHead.find(new_slot.slot_id)).to have_attributes(
      decision_id: "D-project"
    )
    repository_partition = Coordinator::Read::DecisionPartitionHead.find(old_partition.partition_id)
    expect(repository_partition).to have_attributes(
      decision_id: "D-project",
      partition_revision: 1,
      change_kind: "corrected"
    )
    expect(repository_partition.active_decisions).to be_empty
    work_item_partition = Coordinator::Read::DecisionPartitionHead.find(new_partition.partition_id)
    expect(work_item_partition).to have_attributes(
      decision_id: "D-project",
      partition_revision: 0,
      change_kind: "corrected"
    )
    expect(work_item_partition.active_decisions).to contain_exactly(
      include("decision_id" => "D-project", "decision_revision" => 2)
    )
  end

  def activation_lifecycle(
    decision_id: "D-project",
    interpretation_id: "I-project",
    message_id: "M-project",
    topic_id: "testing.framework",
    effect: "prefer",
    modality: "should",
    value: InterpretationInput.named_choice("rspec"),
    position_offset: 0,
    partition_revision: 0,
    previous_heads: []
  )
    definition = decision_definition(
      interpretation_id:,
      message_id:,
      topic_id:,
      effect:,
      modality:,
      value:
    )
    slot = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
    partitions = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(definition)
    recorded_payload = Coordinator::Write::Events::DecisionRecordedV1.new(
      decision_id:,
      interpretation_id:,
      source_message_id: message_id,
      source_event: source_reference("UserUtteranceRecorded", "Conversation", "C-#{message_id}", 0),
      proposal_event: source_reference("DecisionInterpretationProposed", "Interpretation", message_id, 0),
      acceptance_event: source_reference("DecisionInterpretationAccepted", "Interpretation", message_id, 1),
      definition:,
      classifier:,
      scope_provenance: scope_provenance(message_id, "repository"),
      recorded_at: "2026-08-30T12:00:00.000000Z"
    )
    recorded = decision_stream_event(
      recorded_payload,
      decision_id:,
      revision: 0,
      position: position_offset + 100
    )
    activated_payload = Coordinator::Write::Events::DecisionActivatedV1.new(
      decision_id:,
      interpretation_id:,
      recorded_event: event_reference(recorded),
      definition_digest: definition.digest,
      slot:,
      partitions:,
      rationale: Coordinator::Write::Decisions::DecisionActivationRationaleV1.new(
        code: "user_confirmed",
        summary: "Activate the accepted policy."
      ),
      activated_at: "2026-08-30T12:01:00.000000Z"
    )
    activated = decision_stream_event(
      activated_payload,
      decision_id:,
      revision: 1,
      position: position_offset + 200,
      causation_id: recorded.id
    )
    head = decision_head(decision_id, 1, activated)
    partition = partitions.sole
    {
      definition:,
      recorded:,
      activated:,
      head:,
      slot:,
      partitions:,
      slot_events: slot ? slot_lifecycle(slot, head, position_offset: position_offset + 300) : [],
      partition_event: partition_event(
        partition,
        head,
        active_heads: [ *previous_heads, head ],
        revision: partition_revision,
        position: position_offset + 500,
        change_kind: "activated"
      )
    }
  end

  def decision_definition(
    interpretation_id:,
    message_id:,
    topic_id: "testing.framework",
    effect: "prefer",
    modality: "should",
    value: InterpretationInput.named_choice("rspec"),
    scope: InterpretationInput.scope(repository_ids: [ repository_id ]),
    relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
  )
    input = InterpretationInput.build(
      interpretation_id:,
      source_message_id: message_id,
      topic_id:,
      effect:,
      modality:,
      value:,
      scope:,
      relations:
    )
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      interpretation_id:,
      source_message_id: message_id,
      source_event: source_reference("UserUtteranceRecorded", "Conversation", "C-#{message_id}", 0),
      source_span: input.fetch(:source_span),
      classifier: input.fetch(:classifier),
      proposed_decision: input.fetch(:proposed_decision),
      scope_provenance: scope_provenance(message_id, scope[:work_item_id] ? "work_item" : "repository"),
      ambiguities: [],
      assessment: { status: "accepted_for_activation", reasons: [], questions: [] },
      proposed_at: "2026-08-30T12:00:00.000000Z"
    )
    Coordinator::Write::Decisions::DecisionDefinitionBuilder.new.call(
      proposal:,
      valid_from_default: "2026-08-30T12:00:00.000000Z"
    )
  end

  def slot_lifecycle(slot, head, position_offset:)
    opened = governance_event(
      Coordinator::Write::Events::DecisionSlotOpenedV1.new(
        slot:,
        opened_by: head,
        opened_at: "2026-08-30T12:02:00.000000Z"
      ),
      stream: Coordinator::Write::StreamFactory.new.decision_slot(slot.slot_id),
      revision: 0,
      position: position_offset
    )
    changed = slot_head_event(slot.slot_id, nil, head, revision: 1, position: position_offset + 100)
    [ opened, changed ]
  end

  def slot_head_event(slot_id, previous_head, head, revision:, position:)
    governance_event(
      Coordinator::Write::Events::DecisionSlotHeadChangedV1.new(
        slot_id:,
        previous_head:,
        head:,
        changed_at: "2026-08-30T12:03:00.000000Z"
      ),
      stream: Coordinator::Write::StreamFactory.new.decision_slot(slot_id),
      revision:,
      position:
    )
  end

  def partition_event(partition, head, active_heads:, revision:, position:, change_kind:)
    governance_event(
      Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
        partition:,
        partition_revision: revision,
        decision: head,
        active_decisions: active_heads,
        change_kind:,
        advanced_at: "2026-08-30T12:04:00.000000Z"
      ),
      stream: Coordinator::Write::StreamFactory.new.decision_partition(partition.partition_id),
      revision:,
      position:
    )
  end

  def decision_stream_event(payload, decision_id:, revision:, position:, causation_id: nil)
    governance_event(
      payload,
      stream: Coordinator::Write::StreamFactory.new.decision(decision_id),
      revision:,
      position:,
      causation_id:
    )
  end

  def governance_event(payload, stream:, revision:, position:, causation_id: nil)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-governance-projector-#{position}",
      policy_version: "decision-governance/v1",
      actor_kind: "orchestrator",
      actor_id: "guidance-host",
      correlation_id:,
      causation_id:
    )
  end

  def classifier
    Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
      id: "classifier-a",
      version: "decision-classifier-v1",
      ontology_version: 1,
      confidence_millionths: 940_000
    )
  end

  def scope_provenance(message_id, anchor_level)
    Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
      kind: "explicit",
      anchor_level:,
      source_message_id: message_id
    )
  end

  def decision_head(decision_id, revision, event)
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id:,
      decision_revision: revision,
      event: event_reference(event)
    )
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "HumanGuidance",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
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
