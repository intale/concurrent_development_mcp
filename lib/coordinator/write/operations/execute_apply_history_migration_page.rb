# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteApplyHistoryMigrationPage
      include Dry::Monads[:result]

      EVENT_TYPES = %w[
        HistoryMigrationPageDependencyWaveApplied
        HistoryMigrationPageApplied
      ].freeze

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
        snapshot = @loader.call(command.page_id)
        decision = @decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        resolved = decision.value!
        return Success(snapshot.dependency_wave_event(command.dependency_wave)) unless resolved.plan

        stream = @stream_factory.history_migration_page(command.page_id)
        physical = build_events(resolved.plan, command:, caused_by:, expected_stream: stream)
        persisted = @event_store.append(stream, physical, expected_revision: snapshot.latest_revision)
        Success(persisted.find { _1.type == "HistoryMigrationPageDependencyWaveApplied" })
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(changed(command))
      end

      private

      def build_events(plan, command:, caused_by:, expected_stream:)
        expected_event_classes = [ Events::HistoryMigrationPageDependencyWaveAppliedV1 ]
        if command.dependency_wave == Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM
          expected_event_classes << Events::HistoryMigrationPageAppliedV1
        end
        unless plan.writes.map { _1.event.class } == expected_event_classes &&
            plan.writes.all? { _1.stream == expected_stream }
          raise InvalidHistoryMigrationHistory, "HistoryMigrationPage application plan is incomplete"
        end

        plan.writes.map do |write|
          @event_factory.build!(
            event: write.event,
            event_id: @id_generator.uuid_v7,
            metadata: metadata(command),
            markers: markers(command),
            caused_by:,
            correlation_id: caused_by.correlation_id
          )
        end
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
        [
          "history-migration-page:#{command.page_id}",
          "history-migration-wave:#{command.dependency_wave}",
          "command:#{command.command_id}"
        ].freeze
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
