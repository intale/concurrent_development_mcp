# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class AgentChoices
      include EventTimestamped

      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def fetch(choice_id)
        record = Coordinator::Read::AgentChoice.find_by(choice_id:)
        record && build(record)
      end

      def fetch_many(choice_ids)
        records = Coordinator::Read::AgentChoice.where(choice_id: choice_ids).index_by(&:choice_id)
        choice_ids.filter_map { |choice_id| records[choice_id] && build(records.fetch(choice_id)) }
      end

      def store_recorded(event:, choice:)
        decision_context = projected_decision_context(event, choice)
        create_from_event(Coordinator::Read::AgentChoice, event:, attributes: {
          choice_id: choice.choice_id,
          choice_type: choice.choice_type,
          observation_status: "recorded",
          selected: choice.selected.to_h,
          alternatives: choice.alternatives.map(&:to_h),
          reason_summary: choice.reason_summary,
          context: choice.context.to_h,
          decision_context: decision_context.to_h,
          context_digest: decision_context.digest,
          assessment: nil,
          recorded_event: event_reference(event).to_h,
          accepted_event: nil,
          recorded_actor: actor(event).to_h,
          accepted_actor: nil,
          recorded_markers: event.markers,
          accepted_markers: nil,
          recorded_metadata: event.metadata,
          accepted_metadata: nil,
          recorded_causation_id: event.causation_id,
          recorded_correlation_id: event.correlation_id,
          accepted_causation_id: nil,
          accepted_correlation_id: nil,
          recorded_at_domain: choice.respond_to?(:recorded_at) ? choice.recorded_at : event.created_at,
          accepted_at_domain: nil,
          recorded_at_store: event.created_at,
          accepted_at_store: nil
        })
      end

      def accept(event:, acceptance:)
        record = Coordinator::Read::AgentChoice.find_by(choice_id: acceptance.choice_id)
        raise ProjectionStateError, "AgentChoiceRecorded must be projected before AgentChoiceAccepted" unless record

        verify_acceptance!(record, event, acceptance)
        save_from_event(record, event:, attributes: {
          observation_status: "accepted",
          assessment: acceptance.assessment.to_h,
          accepted_event: event_reference(event).to_h,
          accepted_actor: actor(event).to_h,
          accepted_markers: event.markers,
          accepted_metadata: event.metadata,
          accepted_causation_id: event.causation_id,
          accepted_correlation_id: event.correlation_id,
          accepted_at_domain: acceptance.respond_to?(:accepted_at) ? acceptance.accepted_at : event.created_at,
          accepted_at_store: event.created_at
        })
        record
      end

      def invalidate(event:, invalidation:, assessment:)
        record = Coordinator::Read::AgentChoice.find_by(choice_id: invalidation.choice_id)
        raise ProjectionStateError, "AgentChoiceAccepted must be projected before invalidation" unless record&.accepted_event

        verify_invalidation!(record, invalidation, assessment)
        save_from_event(record, event:, attributes: {
          observation_status: "invalidated",
          invalidation: {
            assessment_event: event_reference(assessment.assessment_event).to_h,
            decision_change_event: assessment.decision_change.source_event.to_h,
            reason: invalidation.reason
          },
          invalidated_event: event_reference(event).to_h,
          invalidated_actor: actor(event).to_h,
          invalidated_markers: event.markers,
          invalidated_metadata: event.metadata,
          invalidated_causation_id: event.causation_id,
          invalidated_correlation_id: event.correlation_id,
          invalidated_at_domain: event.created_at,
          invalidated_at_store: event.created_at
        })
        record
      end

      private

      def verify_acceptance!(record, event, acceptance)
        if acceptance.is_a?(Coordinator::Write::Events::AgentChoiceAcceptedV2)
          return if event.metadata["context_digest"] == record.context_digest

          raise ProjectionStateError, "AgentChoiceAccepted does not match the projected Decision context"
        end

        recorded_event = Coordinator::Write::EventReference.new(symbolize(record.recorded_event))
        return if recorded_event == acceptance.recorded_event && record.context_digest == acceptance.context_digest

        raise ProjectionStateError, "AgentChoiceAccepted does not reference the projected recorded choice"
      end

      def projected_decision_context(event, choice)
        context = choice.decision_context
        return context if context.is_a?(Coordinator::Write::DecisionContexts::ContextV1)

        document = context.document
        Coordinator::Write::DecisionContexts::ContextV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h),
          resolved_at: event.created_at.utc.iso8601(6)
        )
      end

      def verify_invalidation!(record, invalidation, assessment)
        accepted_event = Coordinator::Write::EventReference.new(symbolize(record.accepted_event))
        return if record.observation_status == "accepted" &&
                  accepted_event == assessment.accepted_choice &&
                  invalidation.choice_id == assessment.choice_id

        raise ProjectionStateError, "AgentChoice invalidation does not close the projected accepted choice"
      end

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

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
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
