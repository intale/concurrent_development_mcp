# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAdvanceHistoryMigrationApplication
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        migration_loader: HistoryMigrations::MigrationLoader.new(event_store:),
        page_loader: HistoryMigrations::PageLoader.new(event_store:),
        decider: Domain::HistoryMigrations::AdvanceApplication.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @migration_loader = migration_loader
        @page_loader = page_loader
        @decider = decider
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
      end

      def call_command(command, caused_by:)
        event_id = @id_generator.uuid_v7
        migration = @migration_loader.call(command.migration_id)
        page = @page_loader.call(command.page_id)
        decision = @decider.call(snapshot: migration, page: page.state, command:)
        return decision if decision.failure?

        resolved = decision.value!
        return Success(migration.checkpoint_event) unless resolved.plan

        stream = @stream_factory.history_migration(command.migration_id)
        write = resolved.plan.writes.sole
        unless write.stream == stream && write.event.is_a?(Events::HistoryMigrationApplicationCursorAdvancedV1)
          raise InvalidHistoryMigrationHistory, "HistoryMigration application progress plan is invalid"
        end

        physical = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: metadata(command),
          markers: markers(command),
          caused_by:,
          correlation_id: caused_by.correlation_id
        )
        Success(@event_store.append(stream, [ physical ], expected_revision: migration.latest_revision).sole)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(changed(command))
      end

      private

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "history-migration-application/v1"
        )
      end

      def markers(command)
        [
          "history-migration:#{command.migration_id}",
          "history-migration-page:#{command.page_id}",
          "command:#{command.command_id}"
        ].freeze
      end

      def changed(command)
        OutcomeError.new(
          code: :history_migration_checkpoint_changed,
          message: "HistoryMigration application cursor changed concurrently; the request may succeed if retried",
          details: { migration_id: command.migration_id, page_id: command.page_id }
        )
      end
    end
  end
end
