# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class RepositoriesV1
      PROJECTION = ProjectionDefinition.new(name: "repositories", version: 1)

      def initialize(
        contract: Contracts::RepositorySourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        catalog: Repositories::RepositoryCatalog.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @catalog = catalog
        @processed_events = processed_events
      end

      def call(event)
        registration = load_registration(event)
        verify_stream_identity!(event, registration)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )

          @catalog.store(event:, registration:)
        end

        nil
      end

      private

      def load_registration(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, registration)
        return if event.stream.stream_id == registration.repository_id && event.stream_revision.zero?

        raise InvalidProjectionSource, "Repository identity does not match its source stream"
      end
    end
  end
end
