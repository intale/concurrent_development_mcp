# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class AgentChoices
      def fetch(choice_id)
        record = Coordinator::Read::AgentChoice.find_by(choice_id:)
        record && build(record)
      end

      def fetch_many(choice_ids)
        records = Coordinator::Read::AgentChoice.where(choice_id: choice_ids).index_by(&:choice_id)
        choice_ids.filter_map { |choice_id| records[choice_id] && build(records.fetch(choice_id)) }
      end

      private

      def build(record)
        AgentChoiceViewV1.new(
          choice_id: record.choice_id,
          choice_type: record.choice_type,
          observation_status: record.observation_status,
          selected: Coordinator::Write::AgentChoices::ChoiceOptionV1.new(symbolize(record.selected)),
          alternatives: record.alternatives.map do |option|
            Coordinator::Write::AgentChoices::ChoiceOptionV1.new(symbolize(option))
          end,
          reason_summary: record.reason_summary,
          context: Coordinator::Write::DecisionContexts::QueryContextV1.new(symbolize(record.context)),
          decision_context: Coordinator::Write::DecisionContexts::ContextV1.new(
            symbolize(record.decision_context)
          ),
          context_digest: record.context_digest,
          assessment: optional_value(Coordinator::Write::AgentChoices::ChoiceAssessmentV1, record.assessment),
          recorded: recorded_evidence(record),
          accepted: accepted_evidence(record),
          invalidation: invalidation_view(record)
        )
      end

      def recorded_evidence(record)
        AgentChoiceLifecycleEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.recorded_event)),
          actor: AttributedActorV1.new(symbolize(record.recorded_actor)),
          markers: record.recorded_markers,
          metadata: record.recorded_metadata,
          occurred_at: record.recorded_at_domain.utc.iso8601(6),
          persisted_at: record.recorded_at_store.utc.iso8601(6),
          causation_id: record.recorded_causation_id,
          correlation_id: record.recorded_correlation_id
        )
      end

      def accepted_evidence(record)
        return unless record.accepted_event && record.accepted_actor && record.accepted_at_domain && record.accepted_at_store

        AgentChoiceLifecycleEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.accepted_event)),
          actor: AttributedActorV1.new(symbolize(record.accepted_actor)),
          markers: record.accepted_markers || [],
          metadata: record.accepted_metadata || {},
          occurred_at: record.accepted_at_domain.utc.iso8601(6),
          persisted_at: record.accepted_at_store.utc.iso8601(6),
          causation_id: record.accepted_causation_id,
          correlation_id: record.accepted_correlation_id
        )
      end

      def invalidation_view(record)
        return unless record.invalidation && record.invalidated_event

        payload = symbolize(record.invalidation)
        AgentChoiceInvalidationViewV1.new(
          assessment_event: Coordinator::Write::EventReference.new(payload.fetch(:assessment_event)),
          decision_change_event: Coordinator::Write::EventReference.new(payload.fetch(:decision_change_event)),
          reason: payload.fetch(:reason),
          evidence: invalidated_evidence(record)
        )
      end

      def invalidated_evidence(record)
        AgentChoiceLifecycleEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.invalidated_event)),
          actor: AttributedActorV1.new(symbolize(record.invalidated_actor)),
          markers: record.invalidated_markers || [],
          metadata: record.invalidated_metadata || {},
          occurred_at: record.invalidated_at_domain.utc.iso8601(6),
          persisted_at: record.invalidated_at_store.utc.iso8601(6),
          causation_id: record.invalidated_causation_id,
          correlation_id: record.invalidated_correlation_id
        )
      end

      def optional_value(type, attributes)
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
