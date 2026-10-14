# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class Resources
      def fetch(resource_id)
        record = Coordinator::Read::Resource.find_by(resource_id:)
        record && build_view(record)
      end

      def page(query)
        relation = Coordinator::Read::Resource.where(repository_id: query.repository_id)
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(lifecycle_status: query.lifecycle_status) if query.lifecycle_status
        relation = relation.where("resource_id > ?", query.after_resource_id) if query.after_resource_id
        rows = relation.order(:resource_id).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_view(_1) }

        ResourcePageV1.new(
          repository_id: query.repository_id,
          items:,
          next_resource_id: has_more ? items.last.resource_id : nil,
          has_more:
        )
      end

      private

      def build_view(record)
        ResourceViewV1.new(
          resource_id: record.resource_id,
          repository_id: record.repository_id,
          kind: record.kind,
          normalized_path: record.normalized_path,
          lifecycle_status: record.lifecycle_status,
          unbinding_reason: record.unbinding_reason,
          registered: evidence(record, :registered),
          latest_transition: evidence(record, :latest_transition)
        )
      end

      def evidence(record, prefix)
        event = record.public_send("#{prefix}_event")
        return unless event

        ResourceSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(event)),
          actor: AttributedActorV1.new(symbolize(record.public_send("#{prefix}_actor"))),
          markers: record.public_send("#{prefix}_markers"),
          metadata: record.public_send("#{prefix}_metadata"),
          global_position: record.public_send("#{prefix}_global_position"),
          occurred_at: record.public_send("#{prefix}_at_domain").utc.iso8601(6),
          persisted_at: record.public_send("#{prefix}_at_store").utc.iso8601(6),
          causation_id: record.public_send("#{prefix}_causation_id"),
          correlation_id: record.public_send("#{prefix}_correlation_id")
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
