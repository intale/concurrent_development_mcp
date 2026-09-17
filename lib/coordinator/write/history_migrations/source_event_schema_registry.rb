# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceEventSchemaRegistry
      POST_REMODEL_DEFINITIONS = EventSchemaRegistry::DEFAULT_DEFINITIONS.slice(
        *PostRemodelContractCatalog::SOURCE_CONTRACTS
      ).freeze
      DEFINITIONS = LegacyEventSchemaRegistry::DEFINITIONS.merge(POST_REMODEL_DEFINITIONS).freeze

      def initialize(registry: EventSchemaRegistry.new(definitions: DEFINITIONS, validators: {}))
        @registry = registry
      end

      def fetch(type:, schema_version:)
        @registry.fetch(type:, schema_version:)
      end

      def load(type:, schema_version:, data:)
        @registry.load(type:, schema_version:, data:)
      end
    end
  end
end
