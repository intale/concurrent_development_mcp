# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAbandonHistoryMigration
      include Dry::Monads[:result]

      POLICY_VERSION = "history-migration-abandonment/v1"

      def initialize(
        event_store:,
        loader: HistoryMigrations::MigrationLoader.new(event_store:),
        decider: Domain::HistoryMigrations::Abandon.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @loader = loader
        @decider = decider
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
      end

      def call_command(command, caused_by: nil)
        event_id = @id_generator.uuid_v7
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        snapshot = @loader.call(command.migration_id)
        decision = @decider.call(snapshot:, command:)
        return decision if decision.failure?

        resolved = decision.value!
        return Success(snapshot.checkpoint_event) unless resolved.plan

        stream = @stream_factory.history_migration(command.migration_id)
        write = resolved.plan.writes.sole
        unless write.stream == stream && write.event.is_a?(Events::HistoryMigrationAbandonedV1)
          raise InvalidHistoryMigrationHistory, "HistoryMigration abandonment plan is invalid"
        end

        physical = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: metadata(command),
          markers: [ "history-migration:#{command.migration_id}", "command:#{command.command_id}" ],
          caused_by:,
          correlation_id:
        )
        Success(@event_store.append(stream, [ physical ], expected_revision: snapshot.latest_revision).sole)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :history_migration_checkpoint_changed,
            message: "HistoryMigration changed concurrently; the request may succeed if retried",
            details: { migration_id: command.migration_id }
          )
        )
      end

      private

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: POLICY_VERSION
        )
      end
    end
  end
end
