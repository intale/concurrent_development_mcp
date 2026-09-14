# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRollResourceBoundaryEpoch < Dry::Operation
      POLICY_VERSION = "resource-boundary-maintenance/v3"

      def initialize(
        event_store:,
        loader: WorkIntentionBoundaryLoader.new(event_store:),
        rollover_policy: WorkIntentionBoundaryRolloverPolicy.new,
        stream_factory: StreamFactory.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new
      )
        @event_store = event_store
        @loader = loader
        @rollover_policy = rollover_policy
        @stream_factory = stream_factory
        @id_generator = id_generator
        @event_factory = event_factory
      end

      def call_command(command, caused_by:)
        steps do
          step(execute(command:, caused_by:))
        end
      end

      private

      def execute(command:, caused_by:)
        replay = load_replay(command)
        return Success(replay) if replay

        loaded = @loader.call(
          [ command.boundary_marker ],
          repository_id: command.repository_id,
          at: command.source_created_at,
          maximum_count: EventQueries::WORK_INTENTION_BOUNDARY_ROLLOVER_MAXIMUM_COUNT,
          to_position: command.source_global_position,
          resolve_active_observations: false
        )
        return loaded if loaded.failure?

        boundary = loaded.value!
        epoch = boundary.epochs.sole
        return Success(nil) unless @rollover_policy.call(
          boundary:,
          epoch:,
          through_global_position: command.source_global_position
        )

        event = Events::ResourceBoundaryEpochRolledV3.new(
          repository_id: command.repository_id,
          boundary_marker: command.boundary_marker,
          epoch: epoch.epoch + 1,
          through_global_position: command.source_global_position
        )
        persisted = @event_factory.build!(
          event:,
          event_id: @id_generator.uuid_v7,
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
          event_id: persisted.id
        )

        Success(
          @event_store.append(
            snapshot_stream(command.repository_id),
            [ persisted ],
            expected_revision: expected_revision(epoch, command.boundary_marker)
          ).sole
        )
      rescue PgEventstore::WrongExpectedTypesRevisionError
        Failure(
          OutcomeError.new(
            code: :concurrency_conflict,
            message: "Resource boundary epoch changed concurrently; the request may succeed if retried",
            details: {
              repository_id: command.repository_id,
              boundary_marker: command.boundary_marker
            }
          )
        )
      end

      def expected_revision(epoch, marker)
        {
          "ResourceBoundaryEpochRolled" => {
            expected_revision: epoch.event ? epoch.event.stream_revision : :no_event,
            markers: [ marker ]
          }
        }
      end

      def snapshot_stream(repository_id)
        @stream_factory.resource_boundary_epoch(repository_id)
      end

      def load_replay(command)
        @event_store.read_marked(
          snapshot_stream(command.repository_id),
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
