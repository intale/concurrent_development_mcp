# frozen_string_literal: true

module Coordinator::Read::Projections
  # Presentation of the trusted native envelope; never invokes event schemas.
  module Source
    module_function

    def reference(event)
      { event_id: event.id, type: event.type, stream_context: event.stream.context,
        stream_name: event.stream.stream_name, stream_id: event.stream.stream_id, stream_revision: event.stream_revision }
    end

    def actor(event)
      { kind: event.metadata.fetch("actor_kind"), id: event.metadata.fetch("actor_id"), authenticated: false }
    end

    def evidence(event, prefix:)
      {
        "#{prefix}_event": reference(event), "#{prefix}_actor": actor(event),
        "#{prefix}_markers": event.markers, "#{prefix}_metadata": event.metadata,
        "#{prefix}_causation_id": event.causation_id, "#{prefix}_correlation_id": event.correlation_id,
        "#{prefix}_global_position": event.global_position,
        "#{prefix}_at_domain": event.created_at, "#{prefix}_at_store": event.created_at
      }
    end
  end
end
