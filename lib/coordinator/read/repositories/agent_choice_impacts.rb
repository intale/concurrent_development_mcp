# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class AgentChoiceImpacts
      def fetch(assessment_id)
        record = Coordinator::Read::AgentChoiceImpact.find_by(assessment_id:)
        record && build(record)
      end

      def fetch_many(assessment_ids)
        records = Coordinator::Read::AgentChoiceImpact.where(assessment_id: assessment_ids)
          .index_by(&:assessment_id)
        assessment_ids.filter_map do |assessment_id|
          records[assessment_id] && build(records.fetch(assessment_id))
        end
      end

      def store_assessment(event:, impact:)
        assessment = impact.assessment
        Coordinator::Read::AgentChoiceImpact.create!(
          assessment_id: impact.assessment_id,
          choice_id: impact.choice_id,
          attempt_id: impact.attempt_id,
          outcome: assessment.outcome,
          reason: assessment.reason,
          policy_version: event.metadata.fetch("policy_version"),
          accepted_choice: impact.accepted_choice.to_h,
          decision_change: impact.decision_change.to_h.merge(
            changed_at: impact.decision_changed_at
          ),
          assessment: assessment.to_h,
          assessment_event: event_reference(event).to_h,
          source_actor: attributed_actor(impact.decision_change.source_actor).to_h,
          assessment_actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          event_global_position: event.global_position,
          assessed_at_domain: event.created_at,
          assessed_at_store: event.created_at
        )
      end

      def page(query)
        relation = Coordinator::Read::AgentChoiceImpact.where(attempt_id: query.attempt_id)
        if query.after_global_position
          relation = relation.where("event_global_position > ?", query.after_global_position)
        end
        rows = relation.order(:event_global_position).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build(_1) }

        AgentChoiceImpactPageV1.new(
          attempt_id: query.attempt_id,
          items:,
          next_global_position: has_more ? items.last.assessment_evidence.global_position : nil,
          has_more:
        )
      end

      private

      def build(record)
        assessment = Coordinator::Write::AgentChoiceImpacts::ImpactAssessmentV2.new(
          symbolize(record.assessment)
        )
        decision_change_attributes = symbolize(record.decision_change)
        decision_changed_at = decision_change_attributes.delete(:changed_at)
        decision_change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2.new(
          decision_change_attributes
        )
        AgentChoiceImpactViewV1.new(
          assessment_id: record.assessment_id,
          choice_id: record.choice_id,
          attempt_id: record.attempt_id,
          outcome: record.outcome,
          reason: record.reason,
          policy_version: record.policy_version,
          accepted_choice: Coordinator::Write::EventReference.new(symbolize(record.accepted_choice)),
          decision_change:,
          decision_changed_at:,
          before_evaluation: assessment.before_evaluation,
          after_evaluation: assessment.after_evaluation,
          source_actor: AttributedActorV1.new(symbolize(record.source_actor)),
          assessment_evidence: assessment_evidence(record)
        )
      end

      def assessment_evidence(record)
        AgentChoiceImpactAssessmentEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.assessment_event)),
          actor: AttributedActorV1.new(symbolize(record.assessment_actor)),
          markers: record.markers,
          metadata: record.metadata,
          global_position: record.event_global_position,
          occurred_at: record.assessed_at_domain.utc.iso8601(6),
          persisted_at: record.assessed_at_store.utc.iso8601(6),
          causation_id: record.causation_id,
          correlation_id: record.correlation_id
        )
      end

      def attributed_actor(actor)
        AttributedActorV1.new(kind: actor.kind, id: actor.id, authenticated: false)
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
