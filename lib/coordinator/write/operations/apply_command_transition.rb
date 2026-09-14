# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ApplyCommandTransition
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        loader: CommandLifecycle::Loader.new(event_store:),
        stream_factory: StreamFactory.new,
        event_factory: EventFactory.new,
        id_generator: IdGenerator.new
      )
        @event_store = event_store
        @loader = loader
        @stream_factory = stream_factory
        @event_factory = event_factory
        @id_generator = id_generator
      end

      def call(command:, decider:, actor:, tool_name:, caused_by:)
        snapshot = @loader.call(command.command_id)
        decision = decider.call(state: snapshot.state, command:)
        return decision if decision.failure?

        event = decision.value!
        unless event
          return Success(
            CommandLifecycle::Transition.new(
              state: snapshot.state,
              terminal_event: snapshot.persisted_events.last
            )
          )
        end

        persisted = append(
          event:,
          latest_revision: snapshot.latest_revision,
          actor:,
          tool_name:,
          caused_by:
        )
        Success(
          CommandLifecycle::Transition.new(
            state: snapshot.state.apply(event),
            terminal_event: persisted
          )
        )
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :concurrency_conflict,
            message: "Command changed concurrently; the request may succeed if retried",
            details: { command_id: command.command_id }
          )
        )
      end

      private

      def append(event:, latest_revision:, actor:, tool_name:, caused_by:)
        persisted = @event_factory.build!(
          event:,
          event_id: @id_generator.uuid_v7,
          metadata: EventMetadata.new(
            command_id: event.command_id,
            actor_kind: actor.kind,
            actor_id: actor.id,
            recorded_by: "coordinator",
            policy_version: "command-lifecycle/v1"
          ),
          markers: [ "command:#{event.command_id}", "tool:#{tool_name}" ],
          caused_by:
        )

        @event_store.append(
          @stream_factory.command(event.command_id),
          [ persisted ],
          expected_revision: latest_revision
        ).sole
      end
    end
  end
end
