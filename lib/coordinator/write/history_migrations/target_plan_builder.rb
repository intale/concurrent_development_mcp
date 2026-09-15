# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetPlanBuilder
      include Dry::Monads[:result]

      PROCESS_RULE_VERSION = "history-migration-transformation/v1"

      def initialize(process_step_planner:, target_event_planner:)
        @process_step_planner = process_step_planner
        @target_event_planner = target_event_planner
      end

      def call(migration_id:, source_event:, transformed_facts:)
        plans = []
        transformed_facts.each do |fact|
          process_step = plan_process_step(migration_id:, source_event:, fact:)
          result = @target_event_planner.call(
            migration_id:,
            source_event:,
            transformation_step: fact.step_name,
            target_stream: fact.target_stream,
            target_event_id: process_step.target_entity_id!,
            target_event_type: fact.event.class.event_type,
            caused_by: process_step.event
          )
          return result if result.failure?

          plans << result.value!
        end
        Success(plans.freeze)
      end

      private

      def plan_process_step(migration_id:, source_event:, fact:)
        @process_step_planner.call(
          source_event:,
          process_name: "history-migration-#{migration_id}",
          step_name: fact.step_name,
          subject_kind: "source-event",
          subject_id: source_event.id,
          rule_version: PROCESS_RULE_VERSION,
          allocate_target_entity: true
        )
      end
    end
  end
end
