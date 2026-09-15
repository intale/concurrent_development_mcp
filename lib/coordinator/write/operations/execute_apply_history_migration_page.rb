# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteApplyHistoryMigrationPage
      include Dry::Monads[:result]

      EVENT_TYPES = [ "HistoryMigrationPageApplied" ].freeze

      def initialize(
        event_store:,
        loader: HistoryMigrations::PageLoader.new(event_store:),
        decider: Domain::HistoryMigrationPages::Apply.new,
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

      def call_command(command, caused_by:)
        event_id = @id_generator.uuid_v7
        snapshot = @loader.call(command.page_id)
        decision = @decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        resolved = decision.value!
        return Success(snapshot.event("HistoryMigrationPageApplied")) unless resolved.plan

        stream = @stream_factory.history_migration_page(command.page_id)
        physical = build_event(resolved.plan, command:, caused_by:, event_id:, expected_stream: stream)
        Success(@event_store.append(stream, [ physical ], expected_revision: snapshot.latest_revision).sole)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(changed(command))
      end

      private

      def build_event(plan, command:, caused_by:, event_id:, expected_stream:)
        unless plan.writes.length == 1 && plan.writes.sole.stream == expected_stream
          raise InvalidHistoryMigrationHistory, "HistoryMigrationPage application plan is incomplete"
        end

        @event_factory.build!(
          event: plan.writes.sole.event,
          event_id:,
          metadata: metadata(command),
          markers: markers(command),
          caused_by:,
          correlation_id: caused_by.correlation_id
        )
      end

      def metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "history-migration-page/v1"
        )
      end

      def markers(command)
        [ "history-migration-page:#{command.page_id}", "command:#{command.command_id}" ].freeze
      end

      def changed(command)
        OutcomeError.new(
          code: :history_migration_page_changed,
          message: "HistoryMigrationPage changed concurrently; the request may succeed if retried",
          details: { page_id: command.page_id }
        )
      end
    end
  end
end
