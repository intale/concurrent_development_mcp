# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetEventPlanner
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-target-event-plan"
      PLAN_EVENT_TYPES = %w[
        HistoryMigrationTargetStreamPlanCreated
        HistoryMigrationTargetEventPlanned
      ].freeze
      PLAN_HEAD = LatestEventReadCriteria.new(event_types: PLAN_EVENT_TYPES)

      def initialize(
        event_store:,
        target_stream_plan_allocator: TargetStreamPlanAllocator.new(event_store:),
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @target_stream_plan_allocator = target_stream_plan_allocator
        @marker_codec = marker_codec
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_event:,
        transformation_step:,
        target_stream:,
        target_event_id:,
        target_event_type:,
        caused_by:
      )
        allocation = @target_stream_plan_allocator.call(migration_id:, target_stream:, caused_by:)
        return allocation if allocation.failure?

        marker_result = marker_for(migration_id:, source_event:, transformation_step:)
        return Failure(marker_result.failure) if marker_result.failure?

        marker = marker_result.value!.marker
        @event_store.multiple do
          resolve(
            migration_id:,
            source_event:,
            transformation_step:,
            target_stream:,
            target_event_id:,
            target_event_type:,
            caused_by:,
            allocation: allocation.value!,
            marker:
          )
        end
      rescue EventHistoryLimitExceeded
        Failure(error(:duplicate_target_plan, source_event:, transformation_step:, event_ids: []))
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(error(:target_plan_changed, source_event:, transformation_step:, event_ids: []))
      end

      private

      def resolve(
        migration_id:,
        source_event:,
        transformation_step:,
        target_stream:,
        target_event_id:,
        target_event_type:,
        caused_by:,
        allocation:,
        marker:
      )
        existing = existing(marker)
        if existing
          return resolve_existing(
            existing,
            migration_id:,
            source_event:,
            transformation_step:,
            target_stream:,
            target_event_id:,
            target_event_type:,
            marker:
          )
        end

        head = @event_store.read_latest(allocation.plan_stream, PLAN_HEAD)
        unless valid_head?(head, allocation:, migration_id:)
          return Failure(
            error(:target_stream_plan_invalid, source_event:, transformation_step:, event_ids: [ head&.id ].compact)
          )
        end

        command = command_for(
          migration_id:,
          source_event:,
          transformation_step:,
          target_stream:,
          target_event_id:,
          target_event_type:,
          plan_id: allocation.plan_stream.stream_id,
          target_revision: next_target_revision(head)
        )
        event = build_event(command, marker:, caused_by:)
        persisted = @event_store.append(
          allocation.plan_stream,
          [ event ],
          expected_revision: head.stream_revision
        ).sole
        Success(plan(persisted, marker:, outcome: "created"))
      end

      def existing(marker)
        @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationTargetStreamPlan",
            event_types: [ "HistoryMigrationTargetEventPlanned" ],
            markers: [ marker ],
            maximum_count: 2,
            direction: :asc
          )
        ).first
      end

      def resolve_existing(
        event,
        migration_id:,
        source_event:,
        transformation_step:,
        target_stream:,
        target_event_id:,
        target_event_type:,
        marker:
      )
        payload = load(event)
        expected = [
          migration_id,
          source_event.id,
          source_event.global_position,
          transformation_step,
          target_event_id,
          target_event_type,
          target_stream.context,
          target_stream.stream_name,
          target_stream.stream_id
        ]
        actual = [
          payload.migration_id,
          payload.source_event_id,
          payload.source_global_position,
          payload.transformation_step,
          payload.target_event.event_id,
          payload.target_event.type,
          payload.target_event.stream_context,
          payload.target_event.stream_name,
          payload.target_event.stream_id
        ]
        unless actual == expected
          return Failure(
            error(
              :existing_target_plan_mismatch,
              source_event:,
              transformation_step:,
              event_ids: [ event.id ]
            )
          )
        end

        Success(plan(event, marker:, outcome: "existing"))
      rescue KeyError, ArgumentError, Dry::Struct::Error
        Failure(
          error(:existing_target_plan_mismatch, source_event:, transformation_step:, event_ids: [ event.id ])
        )
      end

      def valid_head?(event, allocation:, migration_id:)
        return false unless event

        payload = load(event)
        case payload
        when Events::HistoryMigrationTargetStreamPlanCreatedV1
          payload.plan_id == allocation.plan_stream.stream_id &&
            payload.migration_id == migration_id &&
            stream_for(payload) == allocation.target_stream &&
            event.stream_revision.zero?
        when Events::HistoryMigrationTargetEventPlannedV1
          payload.plan_id == allocation.plan_stream.stream_id &&
            payload.migration_id == migration_id &&
            stream_for(payload.target_event) == allocation.target_stream &&
            payload.target_event.stream_revision == event.stream_revision - 1
        else
          false
        end
      rescue KeyError, ArgumentError, Dry::Struct::Error
        false
      end

      def next_target_revision(head)
        return 0 if head.type == "HistoryMigrationTargetStreamPlanCreated"

        load(head).target_event.stream_revision + 1
      end

      def command_for(
        migration_id:,
        source_event:,
        transformation_step:,
        target_stream:,
        target_event_id:,
        target_event_type:,
        plan_id:,
        target_revision:
      )
        Commands::PlanHistoryMigrationTargetEvent.new(
          command_id: @id_generator.uuid_v7,
          actor: Commands::Actor.new(kind: "system", id: "history-migration-planner"),
          event_id: @id_generator.uuid_v7,
          migration_id:,
          plan_id:,
          source_event_id: source_event.id,
          source_global_position: source_event.global_position,
          transformation_step:,
          target_event: EventReference.new(
            event_id: target_event_id,
            type: target_event_type,
            stream_context: target_stream.context,
            stream_name: target_stream.stream_name,
            stream_id: target_stream.stream_id,
            stream_revision: target_revision
          )
        )
      end

      def build_event(command, marker:, caused_by:)
        @event_factory.build!(
          event: Events::HistoryMigrationTargetEventPlannedV1.new(
            migration_id: command.migration_id,
            plan_id: command.plan_id,
            source_event_id: command.source_event_id,
            source_global_position: command.source_global_position,
            transformation_step: command.transformation_step,
            target_event: command.target_event
          ),
          event_id: command.event_id,
          metadata: EventMetadata.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: "history-migration-target-event-plan/v1"
          ),
          markers: [
            marker,
            "history-migration:#{command.migration_id}",
            "migration-source-event:#{command.source_event_id}",
            "target-event:#{command.target_event.event_id}"
          ],
          caused_by:
        )
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

      def plan(event, marker:, outcome:)
        payload = load(event)
        TargetEventPlanV1.new(
          source_event_id: payload.source_event_id,
          source_global_position: payload.source_global_position,
          transformation_step: payload.transformation_step,
          target_event: payload.target_event,
          planning_event: event,
          marker:,
          outcome:
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(value)
        StreamReference.new(
          context: value.respond_to?(:target_stream_context) ? value.target_stream_context : value.stream_context,
          stream_name: value.respond_to?(:target_stream_name) ? value.target_stream_name : value.stream_name,
          stream_id: value.respond_to?(:target_stream_id) ? value.target_stream_id : value.stream_id
        )
      end

      def error(code, source_event:, transformation_step:, event_ids:)
        TargetEventPlanningErrorV1.new(
          code:,
          message: {
            duplicate_target_plan: "A source event transformation step resolved more than one target plan",
            existing_target_plan_mismatch: "The persisted target plan differs from the requested transformation",
            target_plan_changed: "The target stream plan changed concurrently; the request may succeed if retried",
            target_stream_plan_invalid: "The target stream plan has an invalid history"
          }.fetch(code),
          source_event_id: source_event.id,
          transformation_step:,
          event_ids:
        )
      end
    end
  end
end
