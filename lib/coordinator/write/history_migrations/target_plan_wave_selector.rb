# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetPlanWaveSelector
      include Dry::Monads[:result]

      def initialize(event_store:, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_event:, transformed_facts:, dependency_wave:)
        return Failure(inconsistent(source_event)) if transformed_facts.empty?

        facts_by_step = transformed_facts.to_h { [ _1.step_name, _1 ] }
        return Failure(inconsistent(source_event)) unless facts_by_step.length == transformed_facts.length

        payloads = planned_payloads(
          migration_id:,
          source_event:,
          maximum_count: transformed_facts.length
        )
        return Failure(inconsistent(source_event)) unless valid_plan?(
          payloads,
          migration_id:,
          source_event:,
          facts_by_step:
        )

        waves_by_step = payloads.to_h { [ _1.transformation_step, _1.dependency_wave ] }
        Success(
          transformed_facts.select do |fact|
            waves_by_step.fetch(fact.step_name) == dependency_wave
          end.freeze
        )
      rescue EventHistoryLimitExceeded, KeyError, ArgumentError, Dry::Struct::Error
        Failure(inconsistent(source_event))
      end

      private

      def planned_payloads(migration_id:, source_event:, maximum_count:)
        @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationTargetStreamPlan",
            event_types: [ "HistoryMigrationTargetEventPlanned" ],
            markers: [ "migration-source-event:#{source_event.id}" ],
            maximum_count:,
            direction: :asc
          )
        ).map { load(_1) }
      end

      def valid_plan?(payloads, migration_id:, source_event:, facts_by_step:)
        return false unless payloads.length == facts_by_step.length
        return false unless payloads.map(&:transformation_step).uniq.length == payloads.length

        payloads.all? do |payload|
          fact = facts_by_step[payload.transformation_step]
          payload.is_a?(Events::HistoryMigrationTargetEventPlannedV1) &&
            payload.migration_id == migration_id &&
            payload.source_event_id == source_event.id &&
            payload.source_global_position == source_event.global_position &&
            fact && target_matches?(payload.target_event, fact)
        end
      end

      def target_matches?(target_event, fact)
        target_event.type == fact.event.class.event_type &&
          target_event.stream_context == fact.target_stream.context &&
          target_event.stream_name == fact.target_stream.stream_name &&
          target_event.stream_id == fact.target_stream.stream_id
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Persisted target plans do not exactly match the transformed source event",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
