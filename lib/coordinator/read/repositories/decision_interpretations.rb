# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DecisionInterpretations
      include EventTimestamped

      Page = Data.define(:records, :next_after_revision)

      def page(query)
        rows = Coordinator::Read::DecisionInterpretation
          .where(message_id: query.message_id)
          .where("stream_revision > ?", query.after_revision)
          .order(stream_revision: :asc)
          .limit(query.limit + 1)
          .to_a
        has_more = rows.length > query.limit
        records = rows.first(query.limit)

        Page.new(
          records: records.map { build(_1) },
          next_after_revision: has_more ? records.last.stream_revision : nil
        )
      end

      def store_proposal(event:, source:)
        proposal = source.proposal
        create_from_event(Coordinator::Read::DecisionInterpretation, event:, attributes: {
          interpretation_id: proposal.interpretation_id,
          message_id: proposal.source_message_id,
          source_event: source.source_event.to_h,
          source_span: source.source_span.to_h,
          classifier: source.classifier.to_h,
          proposed_decision: proposal.proposed_decision.to_h,
          scope_provenance: source.scope_provenance.to_h,
          ambiguities: source.ambiguities.map(&:to_h),
          assessment: source.assessment.to_h,
          proposal_status: proposal.assessment,
          lifecycle_status: "proposed",
          policy_status: "proposal_only",
          adjudication: nil,
          clarification_required: false,
          actor_kind: event.metadata.fetch("actor_kind"),
          actor_id: event.metadata.fetch("actor_id"),
          event_id: event.id,
          event_type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          proposed_at_domain: event.created_at
        })
      end

      def require_clarification(event:, clarification:)
        record = Coordinator::Read::DecisionInterpretation.find_by!(
          interpretation_id: clarification.interpretation_id,
          message_id: clarification.source_message_id
        )
        questions = clarification_questions(clarification)
        status = if clarification.origin == "adjudication"
                   "needs_classification"
        else
                   record.proposal_status
        end
        attributes = {
          assessment: {
            status:,
            reasons: clarification.reasons,
            questions: questions.map(&:to_h)
          },
          proposal_status: status,
          lifecycle_status: "clarification_required",
          clarification_required: true,
          clarification_event_id: event.id,
          clarification_stream_revision: event.stream_revision,
          clarification_required_at_domain: event.created_at
        }
        if clarification.origin == "adjudication"
          attributes[:adjudication] = build_adjudication(
            event:,
            action: "request_clarification",
            outcome: "clarification_required",
            rationale: normalize_adjudication_rationale("clarification_required", clarification.rationale),
            clarification: Coordinator::Write::Interpretations::AdjudicationClarificationV1.new(
              status:,
              questions:
            ),
            slot: nil,
            adjudicated_at: event.created_at.utc.iso8601(6)
          ).to_h
        end
        save_from_event(record, event:, attributes:)
      end

      def accept(event:, acceptance:)
        record = find_interpretation(acceptance)
        save_from_event(record, event:, attributes: {
          lifecycle_status: "accepted",
          clarification_required: false,
          adjudication: build_adjudication(
            event:,
            action: "accept",
            outcome: "accepted_for_activation",
            rationale: normalize_adjudication_rationale("accepted", acceptance.rationale),
            clarification: nil,
            slot: acceptance.slot,
            adjudicated_at: event.created_at.utc.iso8601(6)
          ).to_h
        })
      end

      def reject(event:, rejection:)
        record = find_interpretation(rejection)
        save_from_event(record, event:, attributes: {
          lifecycle_status: "rejected",
          clarification_required: false,
          adjudication: build_adjudication(
            event:,
            action: "reject",
            outcome: "rejected",
            rationale: normalize_adjudication_rationale("rejected", rejection.rationale),
            clarification: nil,
            slot: nil,
            adjudicated_at: event.created_at.utc.iso8601(6)
          ).to_h
        })
      end

      private

      def clarification_questions(clarification)
        clarification.questions.map.with_index do |question, index|
          Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
            field: "clarification_#{index + 1}",
            prompt: question,
            options: []
          )
        end
      end

      def normalize_adjudication_rationale(code, rationale)
        Coordinator::Write::Interpretations::AdjudicationRationaleV1.new(code:, summary: rationale)
      end

      def build(record)
        InterpretationProposalV1.new(
          interpretation_id: record.interpretation_id,
          message_id: record.message_id,
          source_event: Coordinator::Write::EventReference.new(symbolize(record.source_event)),
          source_span: build_optional(Coordinator::Write::Interpretations::SourceSpanV1, record.source_span),
          classifier: Coordinator::Write::Interpretations::ClassifierAttributionV1.new(symbolize(record.classifier)),
          proposed_decision: Coordinator::Write::Interpretations::ProposedDecisionV1.new(symbolize(record.proposed_decision)),
          scope_provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(symbolize(record.scope_provenance)),
          ambiguities: record.ambiguities.map do |ambiguity|
            Coordinator::Write::Interpretations::InterpretationAmbiguityV1.new(symbolize(ambiguity))
          end,
          assessment: Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(symbolize(record.assessment)),
          lifecycle_status: record.lifecycle_status,
          policy_status: record.policy_status,
          adjudication: build_optional(InterpretationAdjudicationV1, record.adjudication),
          actor: AttributedActorV1.new(
            kind: record.actor_kind,
            id: record.actor_id,
            authenticated: false
          ),
          event: event_reference(record),
          clarification_event: clarification_event_reference(record),
          proposed_at: record.proposed_at_domain.utc.iso8601(6),
          clarification_required_at: record.clarification_required_at_domain&.utc&.iso8601(6),
          causation_id: record.causation_id,
          correlation_id: record.correlation_id
        )
      end

      def event_reference(record)
        Coordinator::Write::EventReference.new(
          event_id: record.event_id,
          type: record.event_type,
          stream_context: record.stream_context,
          stream_name: record.stream_name,
          stream_id: record.stream_id,
          stream_revision: record.stream_revision
        )
      end

      def build_adjudication(event:, action:, outcome:, rationale:, clarification:, slot:, adjudicated_at:)
        InterpretationAdjudicationV1.new(
          action:,
          outcome:,
          rationale:,
          clarification:,
          slot:,
          actor: AttributedActorV1.new(
            kind: event.metadata.fetch("actor_kind"),
            id: event.metadata.fetch("actor_id"),
            authenticated: false
          ),
          event: persisted_event_reference(event),
          adjudicated_at:,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id
        )
      end

      def find_interpretation(lifecycle_event)
        Coordinator::Read::DecisionInterpretation.find_by!(
          interpretation_id: lifecycle_event.interpretation_id,
          message_id: lifecycle_event.source_message_id
        )
      end

      def persisted_event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def clarification_event_reference(record)
        return unless record.clarification_event_id

        Coordinator::Write::EventReference.new(
          event_id: record.clarification_event_id,
          type: "DecisionClarificationRequired",
          stream_context: record.stream_context,
          stream_name: record.stream_name,
          stream_id: record.stream_id,
          stream_revision: record.clarification_stream_revision
        )
      end

      def build_optional(type, attributes)
        type.new(symbolize(attributes)) if attributes
      end

      def symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array
          value.map { symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
