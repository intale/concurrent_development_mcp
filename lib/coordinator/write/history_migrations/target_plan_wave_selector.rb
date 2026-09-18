# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetPlanWaveSelector
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-target-event-plan"
      PLAN_SCAN_MAXIMUM = 4_096

      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        marker_codec: Coordinator::Shared::Markers::CodecV2.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @marker_codec = marker_codec
      end

      def call(migration_id:, source_event:, transformed_facts:, dependency_wave:)
        resolution = find_complete(migration_id:, source_event:, transformed_facts:)
        return resolution if resolution.failure?

        plans = resolution.value!
        return Failure(inconsistent(source_event)) unless plans

        waves_by_step = plans.to_h { [ _1.transformation_step, _1.dependency_wave ] }
        Success(
          transformed_facts.select do |fact|
            waves_by_step.fetch(fact.step_name) == dependency_wave
          end.freeze
        )
      rescue KeyError
        Failure(inconsistent(source_event))
      end

      def includes_wave?(migration_id:, source_event:, dependency_wave:)
        entries = planned_events(source_event:, maximum_count: PLAN_SCAN_MAXIMUM).map { [ _1, load(_1) ] }
        return Success(nil) if entries.empty?
        return Failure(inconsistent(source_event)) unless valid_source_plan?(
          entries,
          migration_id:,
          source_event:
        )

        Success(entries.any? { _2.dependency_wave == dependency_wave })
      rescue EventHistoryLimitExceeded, KeyError, ArgumentError, Dry::Struct::Error
        Failure(inconsistent(source_event))
      end

      def find_complete(migration_id:, source_event:, transformed_facts:)
        if transformed_facts.empty?
          events = planned_events(source_event:, maximum_count: 1)
          return events.empty? ? Success([].freeze) : Failure(inconsistent(source_event))
        end

        facts_by_step = transformed_facts.to_h { [ _1.step_name, _1 ] }
        return Failure(inconsistent(source_event)) unless facts_by_step.length == transformed_facts.length

        events = planned_events(source_event:, maximum_count: transformed_facts.length)
        return Success(nil) if events.empty?

        entries = events.map { [ _1, load(_1) ] }
        return Failure(inconsistent(source_event)) unless valid_plan?(
          entries,
          migration_id:,
          source_event:,
          facts_by_step:
        )

        entries_by_step = entries.to_h do |event, payload|
          [ payload.transformation_step, [ event, payload ] ]
        end
        plans = transformed_facts.map do |fact|
          event, payload = entries_by_step.fetch(fact.step_name)
          marker = marker_for(migration_id:, source_event:, transformation_step: fact.step_name)
          return marker if marker.failure?
          return Failure(inconsistent(source_event)) unless event.markers.include?(marker.value!.marker)

          build_plan(event, payload, marker.value!.marker)
        end
        Success(plans.freeze)
      rescue EventHistoryLimitExceeded, KeyError, ArgumentError, Dry::Struct::Error
        Failure(inconsistent(source_event))
      end

      private

      def planned_events(source_event:, maximum_count:)
        @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationTargetStreamPlan",
            event_types: [ "HistoryMigrationTargetEventPlanned" ],
            markers: [ "migration-source-event:#{source_event.id}" ],
            maximum_count:,
            direction: :asc
          )
        )
      end

      def valid_plan?(entries, migration_id:, source_event:, facts_by_step:)
        return false unless entries.length == facts_by_step.length
        return false unless valid_source_plan?(entries, migration_id:, source_event:)

        entries.all? do |_event, payload|
          fact = facts_by_step[payload.transformation_step]
          fact && target_matches?(payload.target_event, fact)
        end
      end

      def valid_source_plan?(entries, migration_id:, source_event:)
        return false unless entries.map { _2.transformation_step }.uniq.length == entries.length

        entries.all? do |_event, payload|
          payload.is_a?(Events::HistoryMigrationTargetEventPlannedV1) &&
            payload.migration_id == migration_id &&
            payload.source_event_id == source_event.id &&
            payload.source_global_position == source_event.global_position
        end
      end

      def target_matches?(target_event, fact)
        target_event.type == fact.event.class.event_type &&
          target_event.stream_context == fact.target_stream.context &&
          target_event.stream_name == fact.target_stream.stream_name &&
          target_event.stream_id == fact.target_stream.stream_id
      end

      def marker_for(migration_id:, source_event:, transformation_step:)
        @marker_codec.call(
          purpose: MARKER_PURPOSE,
          components: [
            { dimension: "migration-id", value: migration_id },
            { dimension: "source-event", value: source_event.id },
            { dimension: "step", value: transformation_step }
          ]
        )
      end

      def build_plan(event, payload, marker)
        TargetEventPlanV1.new(
          source_event_id: payload.source_event_id,
          source_global_position: payload.source_global_position,
          transformation_step: payload.transformation_step,
          dependency_wave: payload.dependency_wave,
          target_event: payload.target_event,
          planning_event: event,
          marker:,
          outcome: "existing"
        )
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
