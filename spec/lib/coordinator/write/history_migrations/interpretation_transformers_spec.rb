# frozen_string_literal: true

RSpec.describe "history migration interpretation transformers", :event_store do
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
  let(:legacy_work_item_id) { "legacy-interpretation-work-item" }
  let(:legacy_conversation_id) { "legacy-interpretation-conversation" }
  let(:legacy_message_id) { "legacy-interpretation-message" }
  let(:legacy_interpretation_stream) do
    stream("HumanGuidance", "Interpretation", legacy_message_id)
  end

  it "Given two V1 interpretations in one message stream, when migrated, then each has a source-bound UUIDv7 stream and narrow V2 facts" do
    history = persist_history
    upper_position = history.values.last.global_position

    history.each_value do |source_event|
      expect(plan(source_event, upper_position:)).to be_success
    end

    proposed = transform(history.fetch(:first_proposal), upper_position:).value!.sole
    clarification = transform(history.fetch(:clarification), upper_position:).value!.sole
    accepted = transform(history.fetch(:accepted), upper_position:).value!.sole
    second_proposed = transform(history.fetch(:second_proposal), upper_position:).value!.sole
    rejected = transform(history.fetch(:rejected), upper_position:).value!.sole

    expect(proposed.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(second_proposed.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(second_proposed.target_stream).not_to eq(proposed.target_stream)
    expect(proposed.target_stream.stream_id).not_to eq(legacy_message_id)
    expect(proposed.event).to be_a(Coordinator::Write::Events::DecisionInterpretationProposedV2)
    expect(proposed.event).to have_attributes(
      interpretation_id: proposed.target_stream.stream_id,
      source_message_id: history.fetch(:guidance).id,
      source_span: "RSpec",
      assessment: "confirmation_required",
      ambiguities: [ "Repository scope requires confirmation." ]
    )
    expect(proposed.event.proposed_decision.scope.repository_ids).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(proposed.event.proposed_decision.scope.work_item_id).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )
    expect(proposed.metadata_extension).to have_attributes(
      classifier: classifier,
      scope_provenance: have_attributes(source_message_id: history.fetch(:guidance).id)
    )
    expect(proposed.markers).to contain_exactly(
      "message:#{history.fetch(:guidance).id}",
      "interpretation:#{proposed.target_stream.stream_id}"
    )

    expect(clarification.event).to be_a(Coordinator::Write::Events::DecisionClarificationRequiredV2)
    expect(clarification.event.to_h).to eq(
      interpretation_id: proposed.target_stream.stream_id,
      source_message_id: history.fetch(:guidance).id,
      origin: "proposal_assessment",
      reasons: [ "scope_unclear" ],
      questions: [ "Which repository should this interpretation govern?" ],
      rationale: "scope_unclear"
    )

    target_slot = accepted.event.slot
    expect(accepted.event).to be_a(Coordinator::Write::Events::DecisionInterpretationAcceptedV2)
    expect(accepted.event.to_h.keys).to contain_exactly(
      :interpretation_id, :source_message_id, :slot, :rationale
    )
    expect(target_slot.document).to have_attributes(
      source_message_id: history.fetch(:guidance).id,
      exact_scope: proposed.event.proposed_decision.scope
    )
    expect(target_slot.scope_digest).to eq(canonical_json.sha256(target_slot.document.exact_scope.to_h))
    expect(accepted.markers).to include(
      "message:#{history.fetch(:guidance).id}",
      "interpretation-lifecycle:#{proposed.target_stream.stream_id}",
      target_slot.compound_marker.marker
    )

    expect(second_proposed.event).to have_attributes(
      interpretation_id: second_proposed.target_stream.stream_id,
      source_message_id: history.fetch(:guidance).id,
      assessment: "accepted_for_activation"
    )
    expect(rejected.event).to be_a(Coordinator::Write::Events::DecisionInterpretationRejectedV2)
    expect(rejected.event).to have_attributes(
      interpretation_id: second_proposed.target_stream.stream_id,
      source_message_id: history.fetch(:guidance).id,
      rationale: "Use the first interpretation instead."
    )

    history.except(:guidance).each_value do |source_event|
      expect(dispatch(source_event, upper_position:)).to be_success
    end

    first_target = read_target(proposed.target_stream, maximum_count: 3)
    second_target = read_target(second_proposed.target_stream, maximum_count: 2)
    expect(first_target.map(&:type)).to eq(%w[
      DecisionInterpretationProposed DecisionClarificationRequired DecisionInterpretationAccepted
    ])
    expect(second_target.map(&:type)).to eq(%w[
      DecisionInterpretationProposed DecisionInterpretationRejected
    ])
    expect(first_target.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(second_target.map(&:stream_revision)).to eq([ 0, 1 ])
    expect([ *first_target, *second_target ].flat_map { _1.data.keys }).not_to include(
      "source_event", "proposal_event", "classifier", "scope_provenance", "status",
      "proposed_at", "required_at", "accepted_at", "rejected_at"
    )
  end

  def persist_history
    persist_scope_roots
    guidance = persist_guidance
    first_proposal_payload = proposal(
      guidance:,
      interpretation_id: "legacy-interpretation-one",
      assessment: {
        status: "confirmation_required",
        reasons: [ "scope_unclear" ],
        questions: [ clarification_question ]
      },
      ambiguities: [
        {
          field: "scope",
          code: "scope_unclear",
          description: "Repository scope requires confirmation.",
          options: [ "repository" ]
        }
      ]
    )
    first_proposal = persist_payload(
      legacy_interpretation_stream,
      first_proposal_payload,
      markers: [ "message:#{legacy_message_id}", "interpretation:legacy-interpretation-one" ]
    )
    clarification = persist_payload(
      legacy_interpretation_stream,
      Coordinator::Write::Events::DecisionClarificationRequiredV1.new(
        interpretation_id: "legacy-interpretation-one",
        source_message_id: legacy_message_id,
        status: "confirmation_required",
        origin: "proposal_assessment",
        reasons: [ "scope_unclear" ],
        questions: [ clarification_question ],
        rationale: nil,
        required_at: "2026-08-01T10:01:00.000000Z"
      ),
      markers: [ "message:#{legacy_message_id}", "interpretation-lifecycle:legacy-interpretation-one" ],
      caused_by: first_proposal
    )
    accepted = persist_payload(
      legacy_interpretation_stream,
      Coordinator::Write::Events::DecisionInterpretationAcceptedV1.new(
        interpretation_id: "legacy-interpretation-one",
        source_message_id: legacy_message_id,
        proposal_event: event_reference(first_proposal),
        slot: Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(first_proposal_payload),
        rationale: {
          code: "user_confirmed",
          summary: "The proposed reading matches the intended guidance."
        },
        accepted_at: "2026-08-01T10:02:00.000000Z"
      ),
      markers: [ "message:#{legacy_message_id}", "interpretation-lifecycle:legacy-interpretation-one" ],
      caused_by: clarification
    )
    second_proposal_payload = proposal(
      guidance:,
      interpretation_id: "legacy-interpretation-two",
      assessment: { status: "accepted_for_activation", reasons: [], questions: [] },
      name: "minitest"
    )
    second_proposal = persist_payload(
      legacy_interpretation_stream,
      second_proposal_payload,
      markers: [ "message:#{legacy_message_id}", "interpretation:legacy-interpretation-two" ],
      caused_by: accepted
    )
    rejected = persist_payload(
      legacy_interpretation_stream,
      Coordinator::Write::Events::DecisionInterpretationRejectedV1.new(
        interpretation_id: "legacy-interpretation-two",
        source_message_id: legacy_message_id,
        proposal_event: event_reference(second_proposal),
        rationale: {
          code: "superseded_proposal",
          summary: "Use the first interpretation instead."
        },
        rejected_at: "2026-08-01T10:04:00.000000Z"
      ),
      markers: [ "message:#{legacy_message_id}", "interpretation-lifecycle:legacy-interpretation-two" ],
      caused_by: second_proposal
    )

    { guidance:, first_proposal:, clarification:, accepted:, second_proposal:, rejected: }
  end

  def proposal(guidance:, interpretation_id:, assessment:, ambiguities: [], name: "rspec")
    input = InterpretationInput.build(
      interpretation_id:,
      source_message_id: legacy_message_id,
      value: InterpretationInput.named_choice(name),
      scope: InterpretationInput.scope(
        repository_ids: [ legacy_repository_id ],
        work_item_id: legacy_work_item_id
      ),
      ambiguities:
    )
    Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      interpretation_id:,
      source_message_id: legacy_message_id,
      source_event: event_reference(guidance),
      source_span: input.fetch(:source_span),
      classifier: input.fetch(:classifier),
      proposed_decision: input.fetch(:proposed_decision),
      scope_provenance: scope_provenance,
      ambiguities:,
      assessment:,
      proposed_at: "2026-08-01T10:00:00.000000Z"
    )
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), "RepositoryRegistered")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), "WorkItemCreated")
  end

  def persist_guidance
    persist_payload(
      stream("HumanGuidance", "Conversation", legacy_conversation_id),
      Coordinator::Write::Events::UserUtteranceRecordedV1.new(
        message_id: legacy_message_id,
        conversation_id: legacy_conversation_id,
        text: "Use RSpec for this repository.",
        source: "mcp_client",
        anchors: {
          repository_ids: [ legacy_repository_id ],
          change_set_id: nil,
          work_item_id: legacy_work_item_id,
          attempt_id: nil
        },
        recorded_at: "2026-08-01T09:59:00.000000Z"
      ),
      markers: [ "message:#{legacy_message_id}", "conversation:#{legacy_conversation_id}" ]
    )
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
            "actor_id" => "interpretation-migration-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "interpretation-governance/v1"
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

  def read_target(target_stream, maximum_count:)
    target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationProposed DecisionClarificationRequired
          DecisionInterpretationAccepted DecisionInterpretationRejected
        ],
        maximum_count:,
        direction: :asc
      )
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

  def scope_provenance
    {
      kind: "explicit",
      anchor_level: "work_item",
      source_message_id: legacy_message_id
    }
  end

  def clarification_question
    {
      field: "scope",
      prompt: "Which repository should this interpretation govern?",
      options: [ "repository" ]
    }
  end
end
