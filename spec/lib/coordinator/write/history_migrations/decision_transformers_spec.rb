# frozen_string_literal: true

RSpec.describe "history migration Decision transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:canonical_json) { Coordinator::Write::CanonicalJson.new }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_work_item_id) { "legacy-decision-work-item" }
  let(:legacy_decision_id) { "sha256:#{'a' * 64}" }
  let(:legacy_slot_id) { "sha256:#{'b' * 64}" }
  let(:first_interpretation_id) { "legacy-interpretation-one" }
  let(:second_interpretation_id) { "legacy-interpretation-two" }
  let(:decision_stream) { stream("HumanGuidance", "Decision", legacy_decision_id) }
  let(:slot_stream) { stream("HumanGuidance", "DecisionSlot", legacy_slot_id) }

  it "rebuilds Decision facts, UUIDv7 identities, slot heads, and partition deltas" do
    history = persist_history
    upper_position = history.values.last.global_position

    history.each_value do |source_event|
      expect(plan(source_event, upper_position:)).to be_success
    end

    recorded_facts = transform(history.fetch(:recorded), upper_position:).value!
    activated_fact = transform(history.fetch(:activated), upper_position:).value!.sole
    corrected_fact = transform(history.fetch(:corrected), upper_position:).value!.sole
    opened_fact = transform(history.fetch(:slot_opened), upper_position:).value!.sole
    first_slot_head = transform(history.fetch(:slot_activated), upper_position:).value!.sole
    corrected_slot_head = transform(history.fetch(:slot_corrected), upper_position:).value!.sole
    first_partition = transform(history.fetch(:partition_activated), upper_position:).value!.sole
    corrected_partition = transform(history.fetch(:partition_corrected), upper_position:).value!

    recorded, derivation = recorded_facts
    expect(recorded.event).to be_a(Coordinator::Write::Events::DecisionRecordedV2)
    expect(derivation.event).to be_a(Coordinator::Write::Events::DecisionDerivedFromInterpretationV1)
    expect(recorded.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(recorded.target_stream.stream_id).not_to eq(legacy_decision_id)
    expect(recorded.event.definition.scope.repository_ids).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(recorded.event.definition.scope.work_item_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(recorded.event.definition.validity.until_event.stream_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(recorded.event.source_message_id).to eq(history.fetch(:first_guidance).id)
    expect(recorded.metadata_extension).to have_attributes(
      classifier: classifier,
      scope_provenance: have_attributes(source_message_id: history.fetch(:first_guidance).id)
    )
    expect(recorded.metadata_extension.definition_digest).to eq(
      canonical_json.sha256(recorded.event.definition.to_h)
    )
    expect(recorded.event.to_h.keys).to contain_exactly(
      :decision_id, :interpretation_id, :source_message_id, :definition
    )

    expect(activated_fact.event).to be_a(Coordinator::Write::Events::DecisionActivatedV2)
    expect(activated_fact.event.to_h.keys).to contain_exactly(:decision_id, :interpretation_id, :rationale)
    expect(activated_fact.event.rationale).to eq("Activate the accepted policy.")
    expect(activated_fact.metadata_extension.definition_digest).to eq(
      canonical_json.sha256(recorded.event.definition.to_h)
    )
    expect(corrected_fact.event).to be_a(Coordinator::Write::Events::DecisionDefinitionCorrectedV2)
    expect(corrected_fact.event.source_message_id).to eq(history.fetch(:second_guidance).id)
    expect(corrected_fact.event.definition.relations.corrects).to eq([ recorded.event.decision_id ])
    expect(corrected_fact.event.to_h.keys).to contain_exactly(
      :decision_id, :interpretation_id, :source_message_id, :definition, :rationale
    )

    expect(opened_fact.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(opened_fact.target_stream.stream_id).not_to eq(legacy_slot_id)
    expect(opened_fact.event.opened_by).to eq(recorded.event.decision_id)
    expect(first_slot_head.event.head).to have_attributes(
      decision_id: recorded.event.decision_id,
      decision_revision: 2,
      event: have_attributes(type: "DecisionActivated", stream_revision: 2)
    )
    expect(corrected_slot_head.event.head).to have_attributes(
      decision_id: recorded.event.decision_id,
      decision_revision: 3,
      event: have_attributes(type: "DecisionDefinitionCorrected", stream_revision: 3)
    )

    partition_kind, partition_anchor, partition_topic = first_partition.target_stream.stream_id.split(":", 3)
    expect([ partition_kind, partition_topic ]).to eq(%w[workitem testing])
    expect(partition_anchor).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(first_partition.event).to have_attributes(
      partition_revision: 0,
      decision_id: recorded.event.decision_id
    )
    expect(corrected_partition.map { _1.event.class }).to eq([
      Coordinator::Write::Events::DecisionRemovedFromPartitionV1,
      Coordinator::Write::Events::DecisionAddedToPartitionV1
    ])
    expect(corrected_partition.map { _1.event.partition_revision }).to eq([ 1, 2 ])

    history.each_value do |source_event|
      expect(dispatch(source_event, upper_position:)).to be_success
    end

    decision_events = read_target(
      recorded.target_stream,
      event_types: %w[
        DecisionRecorded DecisionDerivedFromInterpretation DecisionActivated DecisionDefinitionCorrected
      ],
      maximum_count: 4
    )
    slot_events = read_target(
      opened_fact.target_stream,
      event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
      maximum_count: 3
    )
    partition_events = read_target(
      first_partition.target_stream,
      event_types: %w[DecisionAddedToPartition DecisionRemovedFromPartition],
      maximum_count: 3
    )
    expect(decision_events.map(&:type)).to eq(%w[
      DecisionRecorded DecisionDerivedFromInterpretation DecisionActivated DecisionDefinitionCorrected
    ])
    expect(decision_events.map(&:stream_revision)).to eq((0..3).to_a)
    expect(slot_events.map(&:type)).to eq(%w[
      DecisionSlotOpened DecisionSlotHeadChanged DecisionSlotHeadChanged
    ])
    expect(partition_events.map(&:type)).to eq(%w[
      DecisionAddedToPartition DecisionRemovedFromPartition DecisionAddedToPartition
    ])
    expect(
      [ *decision_events, *slot_events, *partition_events ].flat_map { _1.data.keys }
    ).not_to include(
      "recorded_at", "activated_at", "corrected_at", "opened_at", "changed_at", "advanced_at",
      "active_decisions", "previous_head", "previous_slot", "previous_partitions"
    )
  end

  def persist_history
    persist_scope_roots
    first_guidance = persist_guidance("legacy-conversation-one", "legacy-message-one")
    first_proposal, first_acceptance, first_proposal_payload = persist_interpretation(
      first_interpretation_id,
      guidance: first_guidance,
      source_message_id: "legacy-message-one",
      name: "rspec"
    )
    second_guidance = persist_guidance("legacy-conversation-two", "legacy-message-two")
    second_proposal, second_acceptance, second_proposal_payload = persist_interpretation(
      second_interpretation_id,
      guidance: second_guidance,
      source_message_id: "legacy-message-two",
      name: "minitest",
      corrects: [ legacy_decision_id ]
    )

    initial_definition = definition(first_proposal_payload)
    corrected_definition = definition(second_proposal_payload)
    slot = legacy_slot(initial_definition)
    partition = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(initial_definition).sole

    recorded = persist_payload(
      decision_stream,
      Coordinator::Write::Events::DecisionRecordedV1.new(
        decision_id: legacy_decision_id,
        interpretation_id: first_interpretation_id,
        source_message_id: "legacy-message-one",
        source_event: event_reference(first_guidance),
        proposal_event: event_reference(first_proposal),
        acceptance_event: event_reference(first_acceptance),
        definition: initial_definition,
        classifier:,
        scope_provenance: scope_provenance("legacy-message-one"),
        recorded_at: "2026-08-01T10:00:00.000000Z"
      )
    )
    activated = persist_payload(
      decision_stream,
      Coordinator::Write::HistoryMigrations::LegacyEvents::DecisionActivatedV1.new(
        decision_id: legacy_decision_id,
        interpretation_id: first_interpretation_id,
        recorded_event: event_reference(recorded),
        definition_digest: initial_definition.digest,
        slot:,
        partitions: [ partition ],
        rationale: activation_rationale,
        activated_at: "2026-08-01T10:01:00.000000Z"
      ),
      caused_by: recorded
    )
    activated_head = decision_head(activated)
    slot_opened = persist_payload(
      slot_stream,
      Coordinator::Write::HistoryMigrations::LegacyEvents::DecisionSlotOpenedV1.new(
        slot:,
        opened_by: activated_head,
        opened_at: "2026-08-01T10:02:00.000000Z"
      ),
      caused_by: activated
    )
    slot_activated = persist_payload(
      slot_stream,
      Coordinator::Write::Events::DecisionSlotHeadChangedV1.new(
        slot_id: legacy_slot_id,
        previous_head: nil,
        head: activated_head,
        changed_at: "2026-08-01T10:03:00.000000Z"
      ),
      caused_by: slot_opened
    )
    partition_stream = stream("HumanGuidance", "DecisionPartition", partition.partition_id)
    partition_activated = persist_partition(
      partition_stream,
      partition:,
      head: activated_head,
      active_decisions: [ activated_head ],
      change_kind: "activated",
      caused_by: activated
    )
    corrected = persist_payload(
      decision_stream,
      Coordinator::Write::HistoryMigrations::LegacyEvents::DecisionDefinitionCorrectedV1.new(
        decision_id: legacy_decision_id,
        interpretation_id: second_interpretation_id,
        source_message_id: "legacy-message-two",
        source_event: event_reference(second_guidance),
        proposal_event: event_reference(second_proposal),
        acceptance_event: event_reference(second_acceptance),
        previous_head: activated_head,
        previous_definition_digest: initial_definition.digest,
        definition: corrected_definition,
        classifier:,
        scope_provenance: scope_provenance("legacy-message-two"),
        previous_slot: slot,
        slot:,
        previous_partitions: [ partition ],
        partitions: [ partition ],
        rationale: correction_rationale,
        corrected_at: "2026-08-01T10:04:00.000000Z"
      ),
      caused_by: second_acceptance
    )
    corrected_head = decision_head(corrected)
    slot_corrected = persist_payload(
      slot_stream,
      Coordinator::Write::Events::DecisionSlotHeadChangedV1.new(
        slot_id: legacy_slot_id,
        previous_head: activated_head,
        head: corrected_head,
        changed_at: "2026-08-01T10:05:00.000000Z"
      ),
      caused_by: corrected
    )
    partition_corrected = persist_partition(
      partition_stream,
      partition:,
      head: corrected_head,
      active_decisions: [ corrected_head ],
      change_kind: "corrected",
      caused_by: corrected
    )

    {
      first_guidance:, first_proposal:, first_acceptance:,
      second_guidance:, second_proposal:, second_acceptance:,
      recorded:, activated:, slot_opened:, slot_activated:, partition_activated:,
      corrected:, slot_corrected:, partition_corrected:
    }
  end

  def proposal_payload(interpretation_id:, source_message_id:, guidance:, name:, corrects: [])
    input = InterpretationInput.build(
      interpretation_id:,
      source_message_id:,
      value: InterpretationInput.named_choice(name),
      scope: InterpretationInput.scope(
        repository_ids: [ legacy_repository_id ],
        work_item_id: legacy_work_item_id
      ),
      validity: {
        valid_from: nil,
        valid_until: nil,
        until_event: {
          event_type: "WorkItemCompleted",
          stream_context: "DevelopmentExecution",
          stream_name: "WorkItem",
          stream_id: legacy_work_item_id
        }
      },
      relations: { corrects:, supersedes: [], exception_to: [], revokes: [] }
    )
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      interpretation_id:,
      source_message_id:,
      source_event: event_reference(guidance),
      source_span: input.fetch(:source_span),
      classifier: input.fetch(:classifier),
      proposed_decision: input.fetch(:proposed_decision),
      scope_provenance: scope_provenance(source_message_id),
      ambiguities: [],
      assessment: { status: "accepted_for_activation", reasons: [], questions: [] },
      proposed_at: "2026-08-01T09:59:00.000000Z"
    )
    proposal
  end

  def definition(proposal)
    Coordinator::Write::Decisions::DecisionDefinitionBuilder.new.call(
      proposal:,
      valid_from_default: "2026-08-01T10:00:00.000000Z"
    )
  end

  def legacy_slot(definition)
    current = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(definition)
    Coordinator::Write::HistoryMigrations::LegacyEvents::DecisionSlotV1.new(
      slot_id: legacy_slot_id,
      document: current.document,
      compound_marker: current.compound_marker
    )
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), "RepositoryRegistered")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), "WorkItemCreated")
  end

  def persist_guidance(conversation_id, message_id)
    payload = Coordinator::Write::Events::UserUtteranceRecordedV1.new(
      message_id:,
      conversation_id:,
      text: "Use the selected testing framework.",
      source: "mcp_client",
      anchors: {
        repository_ids: [ legacy_repository_id ],
        change_set_id: nil,
        work_item_id: legacy_work_item_id,
        attempt_id: nil
      },
      recorded_at: "2026-08-01T09:58:00.000000Z"
    )
    persist_payload(
      stream("HumanGuidance", "Conversation", conversation_id),
      payload,
      markers: [ "message:#{message_id}", "conversation:#{conversation_id}" ]
    )
  end

  def persist_interpretation(interpretation_id, guidance:, source_message_id:, name:, corrects: [])
    target = stream("HumanGuidance", "Interpretation", source_message_id)
    payload = proposal_payload(
      interpretation_id:,
      source_message_id:,
      guidance:,
      name:,
      corrects:
    )
    proposal = persist_payload(
      target,
      payload,
      markers: [ "message:#{source_message_id}", "interpretation:#{interpretation_id}" ]
    )
    acceptance = persist_payload(
      target,
      Coordinator::Write::Events::DecisionInterpretationAcceptedV1.new(
        interpretation_id:,
        source_message_id:,
        proposal_event: event_reference(proposal),
        slot: Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(payload),
        rationale: {
          code: "user_confirmed",
          summary: "The proposed reading matches the intended guidance."
        },
        accepted_at: "2026-08-01T09:59:30.000000Z"
      ),
      markers: [ "message:#{source_message_id}", "interpretation-lifecycle:#{interpretation_id}" ],
      caused_by: proposal
    )
    [ proposal, acceptance, payload ]
  end

  def persist_partition(target_stream, partition:, head:, active_decisions:, change_kind:, caused_by:)
    persist_payload(
      target_stream,
      Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
        partition:,
        partition_revision: target_stream_revision(target_stream),
        decision: head,
        active_decisions:,
        change_kind:,
        advanced_at: "2026-08-01T10:06:00.000000Z"
      ),
      caused_by:
    )
  end

  def target_stream_revision(target_stream)
    latest = source_store.read_latest(
      target_stream,
      Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "DecisionPartitionAdvanced" ])
    )
    latest ? latest.stream_revision + 1 : 0
  end

  def persist_payload(target_stream, payload, markers: [], caused_by: nil)
    persist_raw(
      target_stream,
      payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      markers:,
      caused_by:
    )
  end

  def persist_raw(target_stream, type, data: {}, schema_version: 1, markers: [], caused_by: nil)
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "decision-migration-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "decision-governance/v1"
          },
          markers:,
          caused_by:,
          correlation_id:
        )
      ]
    ).sole
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def read_target(target_stream, event_types:, maximum_count:)
    target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types:,
        maximum_count:,
        direction: :asc
      )
    )
  end

  def decision_head(event)
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: legacy_decision_id,
      decision_revision: event.stream_revision,
      event: event_reference(event)
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

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end

  def classifier
    Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
      id: "classifier-a",
      version: "decision-classifier-v1",
      ontology_version: 1,
      confidence_millionths: 940_000
    )
  end

  def scope_provenance(message_id)
    Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
      kind: "explicit",
      anchor_level: "work_item",
      source_message_id: message_id
    )
  end

  def activation_rationale
    Coordinator::Write::Decisions::DecisionActivationRationaleV1.new(
      code: "user_confirmed",
      summary: "Activate the accepted policy."
    )
  end

  def correction_rationale
    Coordinator::Write::Decisions::DecisionCorrectionRationaleV1.new(
      code: "normalization_corrected",
      summary: "Apply the accepted correction."
    )
  end
end
