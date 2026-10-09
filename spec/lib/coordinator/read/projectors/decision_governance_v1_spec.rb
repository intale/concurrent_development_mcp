# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionGovernanceV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(
      interpretation_evidence_loader: Coordinator::Read::Decisions::InterpretationEvidenceLoader.new(event_store:)
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects narrow native facts idempotently while serving the recorded stage" do
    lifecycle = activation_lifecycle
    recorded = lifecycle.fetch(:recorded)
    activated = lifecycle.fetch(:activated)
    projector.call(recorded)
    projector.call(recorded)

    available = repository.fetch("D-project")
    expect(available).to have_attributes(
      interpretation_id: "I-project", policy_status: "recorded", activated: nil
    )
    expect(available.recorded.to_h).to include(
      event: include(event_id: recorded.id, stream_revision: 0),
      actor: include(kind: "orchestrator", id: "guidance-host", authenticated: false),
      causation_id: recorded.causation_id,
      correlation_id:
    )

    lifecycle.fetch(:events).drop(1).each { projector.call(_1); projector.call(_1) }
    projected = repository.fetch("D-project")
    expect(projected).to have_attributes(policy_status: "active")
    expect(projected.definition.document).to have_attributes(effect: "prefer", modality: "should")
    expect(projected.slot.slot_id).to eq(lifecycle.fetch(:slot).slot_id)
    expect(projected.partitions.sole.partition_id).to eq("repo:#{repository_id}:testing")
    expect(projected.activated.event.event_id).to eq(activated.id)
    expect(projected.activated.occurred_at).to eq(activated.created_at.utc.iso8601(6))
    expect(Coordinator::Read::DecisionDefinition.sole.updated_at).to eq(lifecycle.fetch(:events).fetch(3).created_at)
    expect(Coordinator::Read::DecisionPartitionHead.sole.active_decisions).to contain_exactly(
      include("decision_id" => "D-project", "decision_revision" => 1)
    )
    expect(Coordinator::Read::DecisionDefinition.count).to eq(1)
    expect(processed_events.count).to eq(lifecycle.fetch(:events).length)
  end

  it "accumulates ordered membership deltas across decisions and ignores older duplicate delivery" do
    first = activation_lifecycle(
      decision_id: "D-A", interpretation_id: "I-A", message_id: "M-A",
      topic_id: "testing.required_suites", effect: "require", modality: "must",
      value: InterpretationInput.string_set(%w[rspec cucumber])
    )
    second = activation_lifecycle(
      decision_id: "D-B", interpretation_id: "I-B", message_id: "M-B",
      topic_id: "testing.required_suites", effect: "require", modality: "must",
      value: InterpretationInput.string_set(%w[rspec mutation])
    )
    [ first, second ].each { |lifecycle| lifecycle.fetch(:events).each { projector.call(_1) } }
    projector.call(first.fetch(:events).last)

    partition = Coordinator::Read::DecisionPartitionHead.sole
    expect(partition).to have_attributes(partition_revision: 1, decision_id: "D-B")
    expect(partition.active_decisions.map { _1.fetch("decision_id") }).to eq(%w[D-A D-B])
    expect(partition.updated_at).to eq(second.fetch(:events).last.created_at)
  end

  it "moves corrected policy between slots and partitions without withholding the earlier projection" do
    initial = activation_lifecycle
    initial.fetch(:events).each { projector.call(_1) }
    earlier = repository.fetch("D-project")
    definition = decision_definition(
      interpretation_id: "I-correction", message_id: "M-correction",
      value: InterpretationInput.named_choice("minitest"),
      scope: InterpretationInput.scope(repository_ids: [ repository_id ], work_item_id: "W-42"),
      relations: { corrects: [ "D-project" ], supersedes: [], exception_to: [], revokes: [] }
    )
    persist_interpretation("I-correction", "M-correction", definition, anchor_level: "work_item")
    correction = append_event(
      Coordinator::Write::Events::DecisionDefinitionCorrectedV2.new(
        decision_id: "D-project", interpretation_id: "I-correction", source_message_id: "M-correction",
        definition: definition.document, rationale: "Apply the accepted correction."
      ),
      streams.decision("D-project"), caused_by: initial.fetch(:activated)
    )
    expect(repository.fetch("D-project").definition.digest).to eq(earlier.definition.digest)
    projector.call(correction)
    projector.call(correction)

    corrected = repository.fetch("D-project")
    expect(corrected).to have_attributes(
      interpretation_id: "I-correction", source_message_id: "M-correction", policy_status: "active",
      previous_definition_digest: earlier.definition.digest, correction_count: 1
    )
    expect(corrected.definition.document.value.name).to eq("minitest")
    expect(corrected.correction_rationale.code).to eq("corrected")
    expect(corrected.corrected.event.event_id).to eq(correction.id)
    expect(Coordinator::Read::DecisionDefinition.sole.updated_at).to eq(correction.created_at)

    new_slot = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
    head = decision_head("D-project", correction)
    changes = [
      append_event(
        Coordinator::Write::Events::DecisionSlotHeadChangedV2.new(slot_id: initial.fetch(:slot).slot_id, head: nil),
        streams.decision_slot(initial.fetch(:slot).slot_id), caused_by: correction
      ),
      *slot_lifecycle(new_slot, head),
      partition_event(initial.fetch(:partitions).sole, "D-project", removed: true),
      partition_event(Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(definition).sole, "D-project")
    ]
    changes.each { projector.call(_1); projector.call(_1) }
    expect(Coordinator::Read::DecisionSlotHead.find(initial.fetch(:slot).slot_id).head).to be_nil
    expect(Coordinator::Read::DecisionSlotHead.find(new_slot.slot_id).decision_id).to eq("D-project")
    expect(repository.fetch("D-project").slot.slot_id).to eq(new_slot.slot_id)
    old_partition = Coordinator::Read::DecisionPartitionHead.find(initial.fetch(:partitions).sole.partition_id)
    expect(old_partition.active_decisions).to be_empty
    expect(old_partition.updated_at).to eq(changes.fetch(-2).created_at)
    new_partition = Coordinator::Read::DecisionPartitionHead.find("workitem:W-42:testing")
    expect(new_partition.active_decisions).to contain_exactly(
      include("decision_id" => "D-project", "decision_revision" => correction.stream_revision)
    )
    expect(new_partition.updated_at).to eq(changes.last.created_at)
  end

  it "rolls back the delivery claim when activation arrives before its recorded projection" do
    lifecycle = activation_lifecycle
    expect { projector.call(lifecycle.fetch(:activated)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(processed_events).to be_empty
    lifecycle.fetch(:events).each { projector.call(_1) }
    expect(repository.fetch("D-project").policy_status).to eq("active")
  end

  it "rejects mismatched identity and missing interpretation evidence before committing a delivery claim" do
    definition = decision_definition(interpretation_id: "I-missing", message_id: "M-missing")
    payload = Coordinator::Write::Events::DecisionRecordedV2.new(
      decision_id: "D-missing", interpretation_id: "I-missing", source_message_id: "M-missing",
      definition: definition.document
    )
    wrong = append_event(payload, streams.decision("D-other"))
    expect { projector.call(wrong) }.to raise_error(Coordinator::Read::InvalidProjectionSource, /identity/)
    missing = append_event(payload, streams.decision("D-missing"))
    expect { projector.call(missing) }.to raise_error(Coordinator::Read::InvalidProjectionSource, /incomplete/)
    expect(processed_events).to be_empty
    expect(Coordinator::Read::DecisionDefinition).not_to exist
  end

  def activation_lifecycle(decision_id: "D-project", interpretation_id: "I-project", message_id: "M-project",
                           topic_id: "testing.framework", effect: "prefer", modality: "should",
                           value: InterpretationInput.named_choice("rspec"))
    definition = decision_definition(interpretation_id:, message_id:, topic_id:, effect:, modality:, value:)
    acceptance = persist_interpretation(interpretation_id, message_id, definition)
    recorded = append_event(
      Coordinator::Write::Events::DecisionRecordedV2.new(
        decision_id:, interpretation_id:, source_message_id: message_id, definition: definition.document
      ), streams.decision(decision_id), caused_by: acceptance
    )
    activated = append_event(
      Coordinator::Write::Events::DecisionActivatedV2.new(
        decision_id:, interpretation_id:, rationale: "Activate the accepted policy."
      ), streams.decision(decision_id), caused_by: recorded
    )
    slot = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
    partitions = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(definition)
    events = [ recorded, activated, *(slot ? slot_lifecycle(slot, decision_head(decision_id, activated)) : []),
               partition_event(partitions.sole, decision_id) ]
    { recorded:, activated:, definition:, slot:, partitions:, events: }
  end

  def decision_definition(interpretation_id:, message_id:, topic_id: "testing.framework", effect: "prefer",
                          modality: "should", value: InterpretationInput.named_choice("rspec"),
                          scope: InterpretationInput.scope(repository_ids: [ repository_id ]),
                          relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] })
    input = InterpretationInput.build(
      interpretation_id:, source_message_id: message_id, topic_id:, effect:, modality:, value:, scope:, relations:
    )
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV2.new(
      interpretation_id:, source_message_id: message_id, source_span: "RSpec",
      proposed_decision: input.fetch(:proposed_decision), ambiguities: [], assessment: "accepted_for_activation"
    )
    Coordinator::Write::Decisions::DecisionDefinitionBuilder.new.call(
      proposal:, valid_from_default: "2026-08-30T12:00:00.000000Z"
    )
  end

  def persist_interpretation(interpretation_id, message_id, definition, anchor_level: "repository")
    guidance = append_event(
      Coordinator::Write::Events::UserUtteranceRecordedV2.new(
        message_id:, conversation_id: "C-#{message_id}", source: "user", text: "Use RSpec."
      ), streams.conversation("C-#{message_id}"), markers: [ "message:#{message_id}" ]
    )
    input = InterpretationInput.build
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV2.new(
      interpretation_id:, source_message_id: message_id, source_span: "RSpec",
      proposed_decision: definition.document.to_h.except(:schema, :topic).merge(topic_id: definition.document.topic.topic_id),
      ambiguities: [], assessment: "accepted_for_activation"
    )
    proposed = append_event(
      proposal, streams.interpretation(interpretation_id), caused_by: guidance,
      metadata: Coordinator::Write::Metadata::InterpretationProposalV2.new(
        **common_metadata.to_h, classifier: input.fetch(:classifier),
        scope_provenance: { kind: "explicit", anchor_level:, source_message_id: message_id }
      )
    )
    append_event(
      Coordinator::Write::Events::DecisionInterpretationAcceptedV2.new(
        interpretation_id:, source_message_id: message_id,
        slot: Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(proposal),
        rationale: "The proposed reading matches the guidance."
      ), streams.interpretation(interpretation_id), caused_by: proposed
    )
  end

  def slot_lifecycle(slot, head)
    stream = streams.decision_slot(slot.slot_id)
    opened = append_event(
      Coordinator::Write::Events::DecisionSlotOpenedV2.new(
        slot_id: slot.slot_id, slot: slot.document, opened_by: head.decision_id
      ), stream
    )
    changed = append_event(Coordinator::Write::Events::DecisionSlotHeadChangedV2.new(slot_id: slot.slot_id, head:), stream)
    [ opened, changed ]
  end

  def partition_event(partition, decision_id, removed: false)
    stream = streams.decision_partition(partition.partition_id)
    previous = event_store.read_latest(
      stream, Coordinator::Write::LatestEventReadCriteria.new(event_types: %w[DecisionAddedToPartition DecisionRemovedFromPartition])
    )
    type = removed ? Coordinator::Write::Events::DecisionRemovedFromPartitionV1 : Coordinator::Write::Events::DecisionAddedToPartitionV1
    append_event(type.new(partition_id: partition.partition_id, partition_revision: previous ? previous.stream_revision + 1 : 0, decision_id:), stream)
  end

  def append_event(payload, stream, caused_by: nil, metadata: common_metadata, markers: [])
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload, event_id: SecureRandom.uuid_v7, metadata:, markers:, caused_by:, correlation_id:
    )
    event_store.append(stream, [ event ]).sole
  end

  def common_metadata
    Coordinator::Write::EventMetadata.new(
      command_id: "cmd-governance-projector", actor_kind: "orchestrator", actor_id: "guidance-host",
      recorded_by: "coordinator", policy_version: "decision-governance/v1"
    )
  end

  def decision_head(decision_id, event)
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id:, decision_revision: event.stream_revision, event: event_reference(event)
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id, type: event.type, stream_context: event.stream.context,
      stream_name: event.stream.stream_name, stream_id: event.stream.stream_id, stream_revision: event.stream_revision
    )
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::DecisionGovernance.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "decision_governance")
  end
end
