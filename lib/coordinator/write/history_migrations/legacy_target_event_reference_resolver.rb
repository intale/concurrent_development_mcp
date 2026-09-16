# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyTargetEventReferenceResolver
      include Dry::Monads[:result]

      PROCESS_RULE_VERSION = "history-migration-transformation/v1"

      def initialize(
        event_store:,
        stream_identity_allocator:,
        process_step_planner:,
        target_event_planner:
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @process_step_planner = process_step_planner
        @target_event_planner = target_event_planner
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        target_stream_context:,
        target_stream_name:,
        identity_role:,
        target_event_type:,
        target_step_name:
      )
        referenced_event = locate(source_reference)
        unless valid_reference?(referenced_event, source_reference:, source_upper_position:)
          return Failure(unresolved(source_event, source_reference:))
        end

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: referenced_event,
          target_stream_context:,
          target_stream_name:,
          identity_role:
        )
        return allocation if allocation.failure?

        resolve(
          migration_id:,
          referenced_event:,
          target_stream: allocation.value!.target_stream,
          target_event_type:,
          target_step_name:
        )
      end

      def call_in_stream(
        migration_id:,
        source_upper_position:,
        source_event:,
        source_reference:,
        target_stream:,
        target_event_type:,
        target_step_name:
      )
        referenced_event = locate(source_reference)
        unless valid_reference?(referenced_event, source_reference:, source_upper_position:)
          return Failure(unresolved(source_event, source_reference:))
        end

        resolve(
          migration_id:,
          referenced_event:,
          target_stream:,
          target_event_type:,
          target_step_name:
        )
      end

      private

      def resolve(migration_id:, referenced_event:, target_stream:, target_event_type:, target_step_name:)
        process_step = @process_step_planner.call(
          source_event: referenced_event,
          process_name: "history-migration-#{migration_id}",
          step_name: target_step_name,
          subject_kind: "source-event",
          subject_id: referenced_event.id,
          rule_version: PROCESS_RULE_VERSION,
          allocate_target_entity: true
        )
        target_plan = @target_event_planner.find(
          migration_id:,
          source_event: referenced_event,
          transformation_step: target_step_name,
          target_stream:,
          target_event_id: process_step.target_entity_id!,
          target_event_type:
        )
        return target_plan if target_plan.failure?

        Success(target_plan.value!.target_event)
      end

      def locate(reference)
        @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
      end

      def valid_reference?(event, source_reference:, source_upper_position:)
        event &&
          event.id == source_reference.event_id &&
          event.type == source_reference.type &&
          event.global_position <= source_upper_position
      end

      def unresolved(source_event, source_reference:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Historical source event reference is absent from the frozen source range: #{source_reference.to_h.inspect}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
