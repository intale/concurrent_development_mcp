# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class EventDispatcher
      include Dry::Monads[:result]

      def initialize(transformer_registry:, target_plan_wave_selector:, fact_planner:, target_writer:)
        @transformer_registry = transformer_registry
        @target_plan_wave_selector = target_plan_wave_selector
        @fact_planner = fact_planner
        @target_writer = target_writer
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, dependency_wave:)
        wave = @target_plan_wave_selector.includes_wave?(
          migration_id:,
          source_event:,
          dependency_wave:
        )
        return wave if wave.failure?
        return @target_writer.call(planned_facts: []) if wave.value! == false

        transformation = @transformer_registry.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return transformation if transformation.failure?

        selection = @target_plan_wave_selector.call(
          migration_id:,
          source_event:,
          transformed_facts: transformation.value!,
          dependency_wave:
        )
        return selection if selection.failure?

        selected_facts = selection.value!
        return @target_writer.call(planned_facts: []) if selected_facts.empty?

        plan = @fact_planner.call(
          migration_id:,
          source_config_name:,
          source_event:,
          transformed_facts: selected_facts
        )
        return plan if plan.failure?

        @target_writer.call(planned_facts: plan.value!)
      end
    end
  end
end
