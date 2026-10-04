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

        plans = @target_plan_wave_selector.find_complete(
          migration_id:,
          source_event:,
          transformed_facts: transformation.value!
        )
        return plans if plans.failure?

        waves_by_step = plans.value!.to_h { [ _1.transformation_step, _1.dependency_wave ] }
        selected_facts = transformation.value!.select do |fact|
          waves_by_step.fetch(fact.step_name) == dependency_wave
        end
        return @target_writer.call(planned_facts: []) if selected_facts.empty?

        plan = @fact_planner.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          transformed_facts: selected_facts,
          target_plans: plans.value!
        )
        return plan if plan.failure?

        @target_writer.call(planned_facts: plan.value!)
      end
    end
  end
end
