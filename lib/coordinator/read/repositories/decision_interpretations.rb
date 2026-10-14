# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DecisionInterpretations
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

      private

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
