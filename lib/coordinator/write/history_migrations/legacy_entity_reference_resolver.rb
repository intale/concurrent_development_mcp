# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyEntityReferenceResolver
      include Dry::Monads[:result]

      def initialize(event_store:, stream_identity_allocator:)
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_stream:,
        target_stream_context:,
        target_stream_name:,
        identity_role:
      )
        referenced_event = @event_store.read_at(source_stream, 0)
        unless referenced_event && referenced_event.global_position <= source_upper_position
          return Failure(unresolved(source_event, source_stream:))
        end

        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: referenced_event,
          target_stream_context:,
          target_stream_name:,
          identity_role:
        )
      end

      private

      def unresolved(source_event, source_stream:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Historical source reference is absent from the frozen source range: #{source_stream.to_h.inspect}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
