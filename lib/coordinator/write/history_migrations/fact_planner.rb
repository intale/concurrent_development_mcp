# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class FactPlanner
      include Dry::Monads[:result]

      PROCESS_RULE_VERSION = "history-migration-dispatch/v1"

      def initialize(
        correlation_allocator:,
        process_step_planner:,
        source_builder: MigrationSourceBuilder.new,
        event_factory: EventFactory.new
      )
        @correlation_allocator = correlation_allocator
        @process_step_planner = process_step_planner
        @source_builder = source_builder
        @event_factory = event_factory
      end

      def call(migration_id:, source_config_name:, source_event:, transformed_facts:)
        correlation = @correlation_allocator.call(migration_id:, source_config_name:, source_event:)
        return correlation if correlation.failure?

        source = @source_builder.call(config_name: source_config_name, event: source_event)
        target_correlation_id = correlation.value!.target_correlation_id
        Success(
          transformed_facts.map do |fact|
            plan_fact(
              migration_id:,
              source_event:,
              source:,
              fact:,
              target_correlation_id:
            )
          end
        )
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
        event_id = process_step.target_entity_id!
        target_event_marker = "migration-target-event:#{event_id}"
        event = @event_factory.build!(
          event: fact.event,
          event_id:,
          metadata: MigrationMetadataV1.new(
            command_id: process_step.target_command_id,
            actor_kind: "system",
            actor_id: "history-migration-dispatcher",
            actor_authenticated: false,
            recorded_by: "coordinator",
            policy_version: PROCESS_RULE_VERSION,
            migration_id:,
            migration_source: source
          ),
          markers: fact.markers + [
            target_event_marker,
            "history-migration:#{migration_id}",
            "command:#{process_step.target_command_id}"
          ],
          caused_by: trace_parent(process_step.event, target_correlation_id:),
          correlation_id: target_correlation_id
        )

        PlannedFactV1.new(target_stream: fact.target_stream, event:, target_event_marker:, process_step:)
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
