# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class Resources
      include EventTimestamped

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

      def store(event:, resource:)
        record = Coordinator::Read::Resource.lock.find_by(resource_id: resource.resource_id)
        verify_identity!(record, resource) if record
        record ||= create_skeleton(resource, event:)

        case resource
        when Coordinator::Write::Events::ResourceIdentityV2::Registered
          store_registration(record, event, resource)
        when Coordinator::Write::Events::ResourceIdentityV2::Bound,
             Coordinator::Write::Events::ResourceIdentityV2::Unbound
          store_transition(record, event, resource)
        end

        save_from_event(record, event:) if record.persisted?
        record
      end

      private

      def create_skeleton(resource, event:)
        create_from_event(Coordinator::Read::Resource, event:, attributes: {
          resource_id: resource.resource_id,
          repository_id: resource.repository_id,
          kind: resource.kind,
          normalized_path: resource.normalized_path.unicode_normalize(:nfc),
          lifecycle_status: "registered"
        })
      rescue ActiveRecord::RecordNotUnique
        record = Coordinator::Read::Resource.lock.find_by(resource_id: resource.resource_id)
        verify_identity!(record, resource) if record
        raise unless record

        record
      end

      def store_registration(record, event, resource)
        existing_event_id = record.registered_event&.fetch("event_id", nil)
        return record if existing_event_id == event.id
        raise ProjectionStateError, "Resource has two registration facts" if existing_event_id

        record.assign_attributes(registration_attributes(event, resource))
        record
      end

      def store_transition(record, event, resource)
        latest_position = record.latest_transition_global_position
        return record if latest_position && latest_position >= event.global_position

        record.assign_attributes(transition_attributes(event, resource))
        record
      end

      def registration_attributes(event, resource)
        evidence_attributes(event, occurred_at: event.created_at, prefix: :registered).merge(
          lifecycle_status: "registered"
        )
      end

      def transition_attributes(event, resource)
        bound = resource.is_a?(Coordinator::Write::Events::ResourceIdentityV2::Bound)
        occurred_at = event.created_at
        evidence_attributes(event, occurred_at:, prefix: :latest_transition).merge(
          lifecycle_status: bound ? "current" : "inactive",
          unbinding_reason: bound ? nil : resource.reason
        )
      end

      def evidence_attributes(event, occurred_at:, prefix:)
        {
          "#{prefix}_event": event_reference(event).to_h,
          "#{prefix}_actor": actor(event).to_h,
          "#{prefix}_markers": event.markers,
          "#{prefix}_metadata": event.metadata,
          "#{prefix}_causation_id": event.causation_id,
          "#{prefix}_correlation_id": event.correlation_id,
          "#{prefix}_global_position": event.global_position,
          "#{prefix}_at_domain": occurred_at,
          "#{prefix}_at_store": event.created_at
        }
      end

      def verify_identity!(record, resource)
        matches = record.repository_id == resource.repository_id &&
                  record.kind == resource.kind &&
                  record.normalized_path == resource.normalized_path.unicode_normalize(:nfc)
        return if matches

        raise ProjectionStateError, "Resource identity changed within its source stream"
      end

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
