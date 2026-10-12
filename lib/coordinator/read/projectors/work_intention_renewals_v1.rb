# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class WorkIntentionRenewalsV1
      PROJECTION = ProjectionDefinition.new(name: "work_intention_renewals", version: 1)

      def initialize(schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        renewals: Repositories::WorkIntentionRenewals.new, processed_events: Repositories::ProcessedProjectionEvents.new,
        contract: Contracts::WorkIntentionRenewalSourceEvent.new)
        @schema_registry, @renewals, @processed_events = schema_registry, renewals, processed_events
        @contract = contract
      end

      def call(event)
        validation = @contract.call(event_type: event.type, schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context, stream_name: event.stream.stream_name, stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision, global_position: event.global_position, correlation_id: event.correlation_id)
        raise InvalidProjectionSource, validation.errors.to_h.inspect if validation.failure?
        payload = @schema_registry.load(type: event.type, schema_version: 1, data: event.data)
        raise InvalidProjectionSource, "Renewal identity does not match the source stream" unless payload.renewal_id == event.stream.stream_id
        identity = ProjectionEventIdentity.from_event(event)
        ApplicationRecord.transaction do
          next unless @processed_events.claim(definition: PROJECTION, identity:, processed_at: event.created_at)
          @renewals.store(event:, payload:)
        end
        nil
      end
    end
  end
end
