# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteStartHistoryMigration < Dry::Operation
      TOOL_NAME = "history_migration_start"
      EVENT_TYPES = [
        "HistoryMigrationCreated",
        "HistoryMigrationSourceStoreSelected",
        "HistoryMigrationTargetStoreSelected",
        "HistoryMigrationSourceRangeFrozen",
        "HistoryMigrationPageSizeSelected",
        "HistoryMigrationStarted"
      ].freeze

      def initialize(
        event_store:,
        preparer: PrepareStartHistoryMigration.new,
        decider: Domain::HistoryMigrations::Start.new,
        input_digest: CommandInputDigest.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        event_ids = EVENT_TYPES.map { @id_generator.uuid_v7 }.freeze
        correlation_id = caused_by&.correlation_id || @id_generator.uuid_v7
        input_digest = @input_digest.call(command)
        stream = @stream_factory.history_migration(command.migration_id)
        physical = load_history(stream)
        state = Domain::HistoryMigrations::State.reduce(physical.map { load_event(_1) })
        decision = @decider.call(state:, command:)
        return decision if decision.failure?

        resolved = decision.value!
        persisted = persist(
          resolved.plan,
          stream:,
          command:,
          event_ids:,
          caused_by:,
          correlation_id:,
          expected_revision: physical.last&.stream_revision || :no_event
        )
        start_event = persisted.last || physical.last
        unless start_event&.type == "HistoryMigrationStarted"
          raise InvalidHistoryMigrationHistory, "HistoryMigration has no terminal start fact"
        end

        Success(
          @completion_builder.history_migration_start(
            command:,
            outcome: resolved.outcome,
            start_event:,
            input_digest:,
            persisted_events: persisted,
            completed_at: start_event.created_at.utc.iso8601(6)
          )
        )
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :history_migration_changed,
            message: "HistoryMigration changed concurrently; the request may succeed if retried",
            details: { migration_id: command.migration_id }
          )
        )
      end

      private

      def load_history(stream)
        @event_store.read(
          stream,
          EventReadCriteria.new(
            event_types: EVENT_TYPES,
            maximum_count: EVENT_TYPES.length,
            direction: :asc
          )
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist(plan, stream:, command:, event_ids:, caused_by:, correlation_id:, expected_revision:)
        return [] unless plan
        unless plan.writes.length == event_ids.length && plan.writes.all? { _1.stream == stream }
          raise InvalidHistoryMigrationHistory, "HistoryMigration start plan must contain its six cohesive facts"
        end

        metadata = EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "history-migration/v1"
        )
        physical = plan.writes.zip(event_ids).map do |write, event_id|
          @event_factory.build!(
            event: write.event,
            event_id:,
            metadata:,
            markers: [
              "history-migration:#{command.migration_id}",
              "command:#{command.command_id}"
            ],
            caused_by:,
            correlation_id:
          )
        end

        @event_store.append(stream, physical, expected_revision:)
      end
    end
  end
end
