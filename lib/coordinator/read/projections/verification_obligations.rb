# frozen_string_literal: true

module Coordinator::Read::Projections
  class VerificationObligations
    def initialize(obligations:, evidence_items:)
      @obligations, @evidence_items = obligations, evidence_items
    end

    def apply(event, definition: nil, outcome: nil)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      id = data.fetch(:obligation_id)
      case event.type
      when "VerificationObligationCreated" then create(definition)
      when "VerificationObligationAddedToChangeSet" then @obligations.assign(data.slice(:obligation_id, :change_set_id))
      when "VerificationObligationClaimed" then claim(event, data)
      when "VerificationEvidenceSubmitted" then evidence(event, data)
      when "VerificationObligationEvidenceNumberChanged"
        @obligations.assign(obligation_id: id, evidence_count: data.fetch(:evidence_number))
      when "VerificationObligationEvidenceCoverageChanged"
        @obligations.assign(data.slice(:obligation_id, :passed_evidence_kinds, :missing_evidence_kinds))
      when "VerificationObligationSatisfied", "VerificationObligationFailed", "VerificationObligationWaived", "VerificationObligationInvalidated"
        @obligations.assign({ obligation_id: id, status: event.type.delete_prefix("VerificationObligation").downcase,
          terminal_outcome: outcome }.merge(envelope(event, prefix: :terminal)).merge(terminal_at_domain: event.created_at))
      end
      @obligations.touch({ obligation_id: id }, time: event.created_at)
      nil
    end

    private

    def create(source)
      definition, event = source.document, source.event
      source_candidate, target = definition.values_at(:source_candidate, :target_candidate)
      attributes = definition.slice(:obligation_id, :kind, :change_set_id, :enforcement).merge(
        source_candidate_id: source_candidate.fetch(:candidate_id), target_candidate_id: target.fetch(:candidate_id),
        source_work_item_id: source_candidate.fetch(:work_item_id), target_work_item_id: target.fetch(:work_item_id),
        source_repository_id: source_candidate.fetch(:repository_id), target_repository_id: target.fetch(:repository_id),
        obligation: definition, event: Source.reference(event), actor: Source.actor(event), markers: event.markers,
        metadata: event.metadata, causation_id: event.causation_id, correlation_id: event.correlation_id,
        event_global_position: event.global_position, created_at_domain: event.created_at, created_at_store: event.created_at)
      @obligations.insert(attributes.merge(status: "open", evidence_count: 0, passed_evidence_kinds: [],
        missing_evidence_kinds: definition.fetch(:required_evidence), created_at: event.created_at, updated_at: event.created_at))
      @obligations.assign(attributes)
    end

    def claim(event, data)
      @obligations.assign({ obligation_id: data.fetch(:obligation_id), claim: data,
        claim_id: data.fetch(:claim_id), claimant_id: data.fetch(:claimant_id), claim_fencing_token: data.fetch(:fencing_token),
        claim_claimed_at_domain: event.created_at, claim_expires_at_domain: data.fetch(:expires_at) }.merge(envelope(event, prefix: :claim)))
    end

    def evidence(event, data)
      assessment = data.fetch(:assessment)
      attributes = data.slice(:evidence_id, :obligation_id, :evidence_kind).merge(assessment.slice(:conclusion, :result_digest),
        assessment_input_digest: event.metadata.fetch("assessment_input_digest"), submission: data,
        event_id: event.id, event: Source.reference(event), actor: Source.actor(event), markers: event.markers,
        metadata: event.metadata, causation_id: event.causation_id, correlation_id: event.correlation_id,
        event_global_position: event.global_position, stream_revision: event.stream_revision,
        produced_at_domain: assessment.fetch(:produced_at), submitted_at_domain: event.created_at, created_at_store: event.created_at)
      @evidence_items.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @evidence_items.assign(attributes)
      @evidence_items.touch(attributes.slice(:evidence_id), time: event.created_at)
    end

    def envelope(event, prefix:)
      { "#{prefix}_event": Source.reference(event), "#{prefix}_actor": Source.actor(event),
        "#{prefix}_markers": event.markers, "#{prefix}_metadata": event.metadata,
        "#{prefix}_causation_id": event.causation_id, "#{prefix}_correlation_id": event.correlation_id,
        "#{prefix}_event_global_position": event.global_position, "#{prefix}_stream_revision": event.stream_revision,
        "#{prefix}_created_at_store": event.created_at }
    end
  end
end
