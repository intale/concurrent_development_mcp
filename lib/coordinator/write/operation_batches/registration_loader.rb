# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class RegistrationLoader
      def initialize(event_store:, request_marker: CommandLifecycle::RequestMarker.new, schema_registry: EventSchemaRegistry.new)
        @event_store, @request_marker, @schema_registry = event_store, request_marker, schema_registry
      end

      def call(actor:, request_id:)
        event = @event_store.read_global_marked(GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl", stream_name: "Command", event_types: [ "CommandRegistered" ],
          markers: [ @request_marker.call(actor:, request_id:) ], maximum_count: 1, direction: :asc)).first
        return unless event
        RegistrationV1.new(payload: @schema_registry.load(type: event.type,
          schema_version: event.metadata.fetch("schema_version"), data: event.data),
          canonical_input_digest: event.metadata.fetch("canonical_input_digest"))
      end
    end
  end
end
