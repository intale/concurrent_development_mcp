# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class SourceBuilder
      def initialize(
        event_store:,
        envelope_contract: Contracts::AgentChoiceImpactSourceEvent.new,
        source_contract: Contracts::AgentChoiceImpactSource.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        reference_builder: EventReferenceBuilder.new
      )
        @event_store = event_store
        @envelope_contract = envelope_contract
        @source_contract = source_contract
        @schema_registry = schema_registry
        @reference_builder = reference_builder
      end

      def call(event)
        verify_envelope!(event)
        persisted = reload(event)
        unless persisted && @reference_builder.call(persisted) == @reference_builder.call(event)
          raise InvalidSourceEvent, "AgentChoice impact source is not the exact persisted event"
        end

        source = SourceV1.new(
          event: persisted,
          reference: @reference_builder.call(persisted),
          payload: load(persisted)
        )
        verify_source!(source)
        source
      rescue Dry::Struct::Error,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise InvalidSourceEvent, error.message
      end

      private

      def verify_envelope!(event)
        result = @envelope_contract.call(event:)
        raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?
      end

      def verify_source!(source)
        result = @source_contract.call(source:)
        raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?
      end

      def reload(event)
        @event_store.read_at(
          Coordinator::Write::StreamReference.new(
            context: event.stream.context,
            stream_name: event.stream.stream_name,
            stream_id: event.stream.stream_id
          ),
          event.stream_revision
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
