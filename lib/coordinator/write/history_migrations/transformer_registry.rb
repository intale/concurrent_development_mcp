# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TransformerRegistry
      include Dry::Monads[:result]

      def initialize(schema_registry: EventSchemaRegistry.new, repository_registered_v1:)
        @schema_registry = schema_registry
        @definitions = {
          [ "RepositoryRegistered", 1 ] => repository_registered_v1
        }.freeze
      end

      def call(migration_id:, source_config_name:, source_event:)
        schema_version = Integer(source_event.metadata.fetch("schema_version"))
        transformer = @definitions[[ source_event.type, schema_version ]]
        return Failure(unsupported(source_event, schema_version:)) unless transformer

        payload = @schema_registry.load(
          type: source_event.type,
          schema_version:,
          data: source_event.data
        )
        transformer.call(migration_id:, source_config_name:, source_event:, source_payload: payload)
      rescue KeyError, ArgumentError, TypeError => error
        Failure(invalid(source_event, error:, schema_version: defined?(schema_version) ? schema_version : nil))
      end

      private

      def unsupported(source_event, schema_version:)
        TransformationErrorV1.new(
          code: :unsupported_source_contract,
          message: "No historical transformation is registered for #{source_event.type}@#{schema_version}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end

      def invalid(source_event, error:, schema_version:)
        TransformationErrorV1.new(
          code: :invalid_source_event,
          message: "Historical source event is invalid: #{error.message}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end
    end
  end
end
