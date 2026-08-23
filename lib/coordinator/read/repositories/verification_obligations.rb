# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class VerificationObligations
      def store_creation(event:, obligation:)
        source = obligation.source_candidate
        target = obligation.target_candidate
        Coordinator::Read::VerificationObligation.create!(
          obligation_id: obligation.obligation_id,
          kind: obligation.kind,
          status: obligation.status,
          change_set_id: obligation.change_set_id,
          source_candidate_id: source.candidate_id,
          target_candidate_id: target.candidate_id,
          source_work_item_id: source.work_item_id,
          target_work_item_id: target.work_item_id,
          source_repository_id: source.repository_id,
          target_repository_id: target.repository_id,
          enforcement: obligation.enforcement,
          obligation: obligation.to_h,
          event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          event_global_position: event.global_position,
          created_at_domain: obligation.created_at,
          created_at_store: event.created_at
        )
      end

      def page(query)
        relation = filtered(Coordinator::Read::VerificationObligation.all, query)
        if query.after_global_position
          relation = relation.where("event_global_position > ?", query.after_global_position)
        end
        rows = relation.order(:event_global_position).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build(_1) }

        VerificationObligationPageV1.new(
          items:,
          next_global_position: has_more ? items.last.evidence.global_position : nil,
          has_more:
        )
      end

      private

      def filtered(relation, query)
        relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
        relation = either(relation, :candidate_id, query.candidate_id) if query.candidate_id
        relation = either(relation, :work_item_id, query.work_item_id) if query.work_item_id
        relation = either(relation, :repository_id, query.repository_id) if query.repository_id
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(enforcement: query.enforcement) if query.enforcement
        relation.where(status: query.status)
      end

      def either(relation, field, value)
        relation.where(
          "source_#{field} = :value OR target_#{field} = :value",
          value:
        )
      end

      def build(record)
        obligation = Coordinator::Write::Events::VerificationObligationCreatedV1.new(
          symbolize(record.obligation)
        )
        VerificationObligationViewV1.new(
          **obligation.to_h,
          evidence: VerificationObligationEvidenceV1.new(
            event: Coordinator::Write::EventReference.new(symbolize(record.event)),
            actor: AttributedActorV1.new(symbolize(record.actor)),
            markers: record.markers,
            metadata: record.metadata,
            global_position: record.event_global_position,
            occurred_at: record.created_at_domain.utc.iso8601(6),
            persisted_at: record.created_at_store.utc.iso8601(6),
            causation_id: record.causation_id,
            correlation_id: record.correlation_id
          )
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

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
