# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class EventDispatcher
      include Dry::Monads[:result]

      def initialize(transformer_registry:, fact_planner:, target_writer:)
        @transformer_registry = transformer_registry
        @fact_planner = fact_planner
        @target_writer = target_writer
      end

      def call(migration_id:, source_config_name:, source_event:)
        transformation = @transformer_registry.call(migration_id:, source_config_name:, source_event:)
        return transformation if transformation.failure?

        plan = @fact_planner.call(
          migration_id:,
          source_config_name:,
          source_event:,
          transformed_facts: transformation.value!
        )
        return plan if plan.failure?

        @target_writer.call(planned_facts: plan.value!)
      end
    end
  end
end
