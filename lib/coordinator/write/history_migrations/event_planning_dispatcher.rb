# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class EventPlanningDispatcher
      include Dry::Monads[:result]

      def initialize(transformer_registry:, target_plan_wave_selector:, target_plan_builder:)
        @transformer_registry = transformer_registry
        @target_plan_wave_selector = target_plan_wave_selector
        @target_plan_builder = target_plan_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:)
        transformation = @transformer_registry.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return transformation if transformation.failure?

        existing = @target_plan_wave_selector.find_complete(
          migration_id:,
          source_event:,
          transformed_facts: transformation.value!
        )
        return existing if existing.failure? || existing.value!

        @target_plan_builder.call(
          migration_id:,
          source_event:,
          transformed_facts: transformation.value!
        )
      end
    end
  end
end
