# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class FactPlanner
      include Dry::Monads[:result]

      PROCESS_RULE_VERSION = "history-migration-transformation/v1"

      def initialize(
        correlation_allocator:,
        process_step_planner:,
        target_event_planner:,
        source_builder: MigrationSourceBuilder.new,
        event_factory: EventFactory.new
      )
        @correlation_allocator = correlation_allocator
        @process_step_planner = process_step_planner
        @target_event_planner = target_event_planner
        @source_builder = source_builder
        @event_factory = event_factory
      end

      def call(migration_id:, source_config_name:, source_event:, transformed_facts:)
        correlation = @correlation_allocator.call(migration_id:, source_config_name:, source_event:)
        return correlation if correlation.failure?

        source = @source_builder.call(config_name: source_config_name, event: source_event)
        target_correlation_id = correlation.value!.target_correlation_id
        planned_facts = []
        transformed_facts.each do |fact|
          planned = plan_fact(
            migration_id:,
            source_event:,
            source:,
            fact:,
            target_correlation_id:
          )
          return planned if planned.failure?

          planned_facts << planned.value!
        end
        Success(planned_facts.freeze)
      end

      private

      def plan_fact(migration_id:, source_event:, source:, fact:, target_correlation_id:)
        process_step = @process_step_planner.call(
          source_event:,
          process_name: "history-migration-#{migration_id}",
          step_name: fact.step_name,
          subject_kind: "source-event",
          subject_id: source_event.id,
          rule_version: PROCESS_RULE_VERSION,
          allocate_target_entity: true
        )
        target_plan = @target_event_planner.find(
          migration_id:,
          source_event:,
          transformation_step: fact.step_name,
          target_stream: fact.target_stream,
          target_event_id: process_step.target_entity_id!,
          target_event_type: fact.event.class.event_type
        )
        return target_plan if target_plan.failure?

        event_id = target_plan.value!.target_event.event_id
        target_event_marker = "migration-target-event:#{event_id}"
        metadata_extension = fact.metadata_extension
        event = @event_factory.build!(
          event: fact.event,
          event_id:,
          metadata: MigrationMetadataV1.new(
            command_id: process_step.target_command_id,
            actor_kind: "system",
            actor_id: "history-migration-dispatcher",
            actor_authenticated: false,
            recorded_by: "coordinator",
            policy_version: metadata_extension&.policy_version || PROCESS_RULE_VERSION,
            migration_id:,
            migration_source: source,
            canonical_input_digest: metadata_extension&.canonical_input_digest
          ),
          markers: fact.markers + [
            target_event_marker,
            "history-migration:#{migration_id}",
            "command:#{process_step.target_command_id}"
          ],
          caused_by: trace_parent(process_step.event, target_correlation_id:),
          correlation_id: target_correlation_id
        )

        Success(
          PlannedFactV1.new(
            target_stream: fact.target_stream,
            event:,
            target_event_marker:,
            process_step:,
            target_event_plan: target_plan.value!
          )
        )
      end

      def trace_parent(process_step_event, target_correlation_id:)
        PgEventstore::Event.new(
          id: process_step_event.id,
          type: process_step_event.type,
          correlation_id: target_correlation_id
        )
      end
    end
  end
end
