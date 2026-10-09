# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::DecisionInterpretationsV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(
      source_loader: Coordinator::Read::Interpretations::ProjectionSourceLoader.new(event_store:)
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:message_id) { SecureRandom.uuid_v7 }
  let(:conversation_id) { SecureRandom.uuid_v7 }
  let(:interpretation_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:stream) { streams.interpretation(interpretation_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects native proposal, clarification and acceptance idempotently with real source evidence" do
    proposal = proposal_event
    clarification = clarification_event(proposal, origin: "proposal_assessment")
    acceptance = append_event(
      Coordinator::Write::Events::DecisionInterpretationAcceptedV2.new(
        interpretation_id:,
        source_message_id: message_id,
        slot: Coordinator::Write::Interpretations::InterpretationSlotBuilder.new.call(proposal_payload),
        rationale: "The proposed reading matches the intended guidance."
      ),
      caused_by: proposal,
      actor_kind: "orchestrator",
      actor_id: "guidance-host"
    )

    [ proposal, proposal, clarification, clarification, acceptance, acceptance ].each { projector.call(_1) }

    projected = projected_interpretation
    expect(projected).to have_attributes(
      interpretation_id:,
      message_id:,
      lifecycle_status: "accepted",
      policy_status: "proposal_only",
      proposed_at: proposal.created_at.utc.iso8601(6)
    )
    expect(projected.assessment.status).to eq("confirmation_required")
    expect(projected.event.to_h).to include(event_id: proposal.id, stream_id: interpretation_id, stream_revision: 0)
    expect(projected.clarification_event.to_h).to include(event_id: clarification.id, stream_revision: 1)
    expect(projected.source_event).to have_attributes(event_id: guidance_event.id, type: "UserUtteranceRecorded")
    expect(projected.source_span).to have_attributes(text: "RSpec", start_character: 4, end_character: 9)
    expect(projected.classifier.id).to eq("classifier-a")
    expect(projected.adjudication.to_h).to include(
      action: "accept",
      outcome: "accepted_for_activation",
      rationale: include(code: "accepted", summary: "The proposed reading matches the intended guidance."),
      event: include(event_id: acceptance.id, type: "DecisionInterpretationAccepted"),
      actor: include(kind: "orchestrator", id: "guidance-host", authenticated: false),
      adjudicated_at: acceptance.created_at.utc.iso8601(6)
    )
    expect(projected.adjudication.slot.compound_marker.marker).to start_with("compound:interpretation-slot:v2|")
    expect(projected.adjudication.correlation_id).to eq(correlation_id)
    expect(projected.causation_id).to eq(guidance_event.id)
    expect(Coordinator::Read::DecisionInterpretation.count).to eq(1)
    expect(Coordinator::Read::DecisionInterpretation.sole.updated_at).to eq(acceptance.created_at)
    expect(processed_events.count).to eq(3)
  end

  it "serves adjudication clarification before rejection without activating policy" do
    proposal = proposal_event
    clarification = clarification_event(proposal, origin: "adjudication")
    rejection = append_event(
      Coordinator::Write::Events::DecisionInterpretationRejectedV2.new(
        interpretation_id:,
        source_message_id: message_id,
        rationale: "The reading does not match the intended guidance."
      ),
      caused_by: proposal,
      actor_kind: "orchestrator",
      actor_id: "guidance-host"
    )

    projector.call(proposal)
    projector.call(clarification)
    clarified = projected_interpretation
    expect(clarified).to have_attributes(lifecycle_status: "clarification_required", policy_status: "proposal_only")
    expect(clarified.assessment.questions.sole.prompt).to eq("Which repository should this interpretation govern?")
    expect(clarified.adjudication.to_h).to include(
      action: "request_clarification",
      outcome: "clarification_required",
      clarification: include(status: "needs_classification"),
      adjudicated_at: clarification.created_at.utc.iso8601(6)
    )

    projector.call(rejection)
    expect(projected_interpretation).to have_attributes(lifecycle_status: "rejected", policy_status: "proposal_only")
    expect(projected_interpretation.adjudication.to_h).to include(
      action: "reject", outcome: "rejected", event: include(event_id: rejection.id),
      adjudicated_at: rejection.created_at.utc.iso8601(6)
    )
  end

  it "rejects a message-keyed interpretation stream before claiming projection delivery" do
    event = ProjectionEventFactory.build(
      payload: proposal_payload,
      stream: streams.interpretation(message_id),
      stream_revision: 0,
      global_position: 100,
      policy_version: "interpretation-proposal/v1"
    )

    expect { projector.call(event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource, "interpretation identity does not match its source stream"
    )
    expect(processed_events).to be_empty
    expect(Coordinator::Read::DecisionInterpretation).not_to exist
  end

  it "rolls back its delivery claim when selected text is absent from persisted guidance" do
    event = proposal_event(payload: Coordinator::Write::Events::DecisionInterpretationProposedV2.new(
      proposal_payload.to_h.merge(source_span: "missing excerpt")
    ))

    expect { projector.call(event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource, "Interpretation source span is not present in guidance"
    )
    expect(processed_events).to be_empty
    expect(Coordinator::Read::DecisionInterpretation).not_to exist
  end

  it "rejects missing classifier provenance without inventing a projection" do
    event = proposal_event(metadata: common_metadata)

    expect { projector.call(event) }.to raise_error(Coordinator::Read::InvalidProjectionSource, /classifier/)
    expect(processed_events).to be_empty
    expect(Coordinator::Read::DecisionInterpretation).not_to exist
  end

  def proposal_payload
    Coordinator::Write::Events::DecisionInterpretationProposedV2.new(
      interpretation_id:,
      source_message_id: message_id,
      source_span: "RSpec",
      proposed_decision: interpretation_input.fetch(:proposed_decision),
      assessment: "confirmation_required",
      ambiguities: []
    )
  end

  def interpretation_input
    InterpretationInput.build(
      interpretation_id:,
      source_message_id: message_id,
      effect: "forbid",
      modality: "must_not",
      scope: InterpretationInput.scope(repository_ids: [ repository_id ], change_set_id: "CS-1"),
      enforcement: InterpretationInput.advisory_enforcement.merge(level: "merge_gate", on_violation: "block")
    )
  end

  def proposal_event(payload: proposal_payload, metadata: proposal_metadata)
    append_event(payload, caused_by: guidance_event, metadata:)
  end

  def guidance_event
    @guidance_event ||= append_event(
      Coordinator::Write::Events::UserUtteranceRecordedV2.new(
        message_id:, conversation_id:, source: "user", text: "Use RSpec for logical assertions."
      ),
      target_stream: streams.conversation(conversation_id),
      markers: [ "message:#{message_id}" ]
    )
  end

  def clarification_event(proposal, origin:)
    append_event(
      Coordinator::Write::Events::DecisionClarificationRequiredV2.new(
        interpretation_id:, source_message_id: message_id, origin:,
        reasons: [ "scope_unclear" ],
        questions: [ "Which repository should this interpretation govern?" ],
        rationale: "The intended repository is unclear."
      ),
      caused_by: proposal,
      actor_kind: "orchestrator",
      actor_id: "guidance-host"
    )
  end

  def proposal_metadata
    Coordinator::Write::Metadata::InterpretationProposalV2.new(
      **common_metadata.to_h,
      classifier: interpretation_input.fetch(:classifier),
      scope_provenance: { kind: "explicit", anchor_level: "change_set", source_message_id: message_id }
    )
  end

  def common_metadata(actor_kind: "agent", actor_id: "classifier-host")
    Coordinator::Write::EventMetadata.new(
      command_id: "cmd-projector-native-interpretation", actor_kind:, actor_id:,
      recorded_by: "coordinator", policy_version: "interpretation-proposal/v1"
    )
  end

  def append_event(payload, target_stream: stream, metadata: nil, markers: [], caused_by: nil,
                   actor_kind: "agent", actor_id: "classifier-host")
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload,
      event_id: SecureRandom.uuid_v7,
      metadata: metadata || common_metadata(actor_kind:, actor_id:),
      markers:,
      caused_by:,
      correlation_id:
    )
    event_store.append(target_stream, [ event ]).sole
  end

  def projected_interpretation
    Coordinator::Read::Repositories::DecisionInterpretations.new.page(
      Coordinator::Read::InterpretationListQueryV1.new(message_id:, after_revision: -1, limit: 20)
    ).records.sole
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "decision_interpretations")
  end
end
