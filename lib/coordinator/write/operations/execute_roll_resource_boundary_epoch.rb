# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRollResourceBoundaryEpoch < Dry::Operation
      POLICY_VERSION = "resource-boundary-maintenance/v1"

      def initialize(
        event_store:,
        loader: ResourceBoundaryLoader.new(event_store:),
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new
      )
        @event_store = event_store
        @loader = loader
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
      end

      def call_command(command, caused_by:)
        event_id = @id_generator.uuid_v7
        rolled_at = @clock.now

        steps do
          step(@event_store.multiple do
            execute(command:, caused_by:, event_id:, rolled_at:)
          end)
        end
      end

      private

      def execute(command:, caused_by:, event_id:, rolled_at:)
        replay = load_replay(command)
        return Success(replay) if replay

        boundary = @loader.call(
          [ command.boundary_marker ],
          maximum_delta_count: EventQueries::RESOURCE_BOUNDARY_ROLLOVER_DELTA_MAXIMUM_COUNT,
          to_position: command.source_global_position,
          strict: false
        ).boundaries.sole
        return Success(nil) unless rollover_required?(boundary)

        active_leases = boundary.states.select { _1.active_at?(rolled_at) }
        if active_leases.length > EventQueries::RESOURCE_BOUNDARY_ACTIVE_LEASE_MAXIMUM_COUNT
          return Failure(
            OutcomeError.new(
              code: :resource_boundary_active_lease_limit_exceeded,
              message: "Resource boundary has too many active leases to snapshot safely",
              details: {
                boundary_marker: command.boundary_marker,
                active_lease_count: active_leases.length,
                maximum_active_lease_count: EventQueries::RESOURCE_BOUNDARY_ACTIVE_LEASE_MAXIMUM_COUNT
              }
            )
          )
        end

        event = build_epoch_event(
          repository_id: command.repository_id,
          boundary_marker: command.boundary_marker,
          epoch: boundary.epoch + 1,
          previous_through_global_position: boundary.previous_through_global_position,
          through_global_position: boundary.through_global_position,
          active_leases:,
          rolled_at:
        )
        persisted = @event_factory.build!(
          event:,
          event_id:,
          metadata: EventMetadata.new(
            command_id: command.command_id,
            actor_kind: command.actor.kind,
            actor_id: command.actor.id,
            recorded_by: "coordinator",
            policy_version: POLICY_VERSION
          ),
          markers: [ command.boundary_marker, "command:#{command.command_id}" ],
          caused_by:
        )
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "resource_boundary_dcb",
          command_id: command.command_id,
          source_event_id: command.source_event_id,
          event_id:
        )

        Success(@event_store.append(@loader.snapshot_stream(command.boundary_marker), [ persisted ]).sole)
      end

      def rollover_required?(boundary)
        boundary.truncated || boundary.delta_count >= EventQueries::RESOURCE_BOUNDARY_ROLLOVER_SOFT_COUNT
      end

      def build_epoch_event(active_leases:, **attributes)
        Events::ResourceBoundaryEpochRolledV2.new(
          **attributes,
          active_leases: active_leases.map { Events::ResourceBoundaryEpochRolledV2::ActiveLeaseV2.from_state(_1) }
        )
      end

      def load_replay(command)
        @event_store.read_marked(
          @loader.snapshot_stream(command.boundary_marker),
          MarkedEventReadCriteria.new(
            event_type: "ResourceBoundaryEpochRolled",
            marker: "command:#{command.command_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).first
      end
    end
  end
end
