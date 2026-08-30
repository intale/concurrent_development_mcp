# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class PersistedPublicationLoader
      include Dry::Monads[:result]

      def initialize(schema_registry: EventSchemaRegistry.new)
        @schema_registry = schema_registry
      end

      def call(event)
        Success(
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        )
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError => error
        Failure(invalid_event(schema_version: event.metadata["schema_version"], errors: { payload: [ error.message ] }))
      end

      private

      def invalid_event(schema_version:, errors:)
        OutcomeError.new(
          code: :stored_skill_revision_invalid,
          message: "Persisted Skill revision is invalid",
          details: { schema_version:, errors: }
        )
      end
    end
  end
end
