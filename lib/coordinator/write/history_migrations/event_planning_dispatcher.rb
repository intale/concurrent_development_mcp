# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class EventPlanningDispatcher
      include Dry::Monads[:result]

      def initialize(transformer_registry:, target_plan_builder:)
        @transformer_registry = transformer_registry
        @target_plan_builder = target_plan_builder
      end

      def call(migration_id:, source_config_name:, source_event:)
        transformation = @transformer_registry.call(migration_id:, source_config_name:, source_event:)
        return transformation if transformation.failure?

        @target_plan_builder.call(
          migration_id:,
          source_event:,
          transformed_facts: transformation.value!
        )
      end
    end
  end
end
