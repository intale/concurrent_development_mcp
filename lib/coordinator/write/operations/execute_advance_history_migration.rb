# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteAdvanceHistoryMigration
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        migration_loader: HistoryMigrations::MigrationLoader.new(event_store:),
        page_loader: HistoryMigrations::PageLoader.new(event_store:),
        decider: Domain::HistoryMigrations::Advance.new,
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
        event_ids = Array.new(2) { @id_generator.uuid_v7 }.freeze
        migration = @migration_loader.call(command.migration_id)
        page = @page_loader.call(command.page_id)
        decision = @decider.call(snapshot: migration, page: page.state, command:)
        return decision if decision.failure?

        resolved = decision.value!
        return Success(migration.checkpoint_event) unless resolved.plan

        stream = @stream_factory.history_migration(command.migration_id)
        physical = build_events(resolved.plan, command:, caused_by:, event_ids:, expected_stream: stream)
        persisted = persist(stream, physical, expected_revision: migration.latest_revision)
        Success(persisted.last)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(changed(command))
      end

      private

      def build_events(plan, command:, caused_by:, event_ids:, expected_stream:)
        unless (1..2).cover?(plan.writes.length) && plan.writes.all? { _1.stream == expected_stream }
          raise InvalidHistoryMigrationHistory, "HistoryMigration progress plan is invalid"
        end

        plan.writes.zip(event_ids).map do |write, event_id|
          @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: metadata(command),
            markers: markers(command),
            caused_by:,
            correlation_id: caused_by.correlation_id
          )
        end
      end

      def persist(stream, events, expected_revision:)
        return @event_store.append(stream, events, expected_revision:) if events.one?

        @event_store.multiple { @event_store.append(stream, events, expected_revision:) }
      end

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "history-migration-progress/v1"
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
          message: "HistoryMigration cursor changed concurrently; the request may succeed if retried",
          details: { migration_id: command.migration_id, page_id: command.page_id }
        )
      end
    end
  end
end
