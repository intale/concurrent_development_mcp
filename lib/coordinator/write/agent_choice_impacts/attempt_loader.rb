# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class AttemptLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(recorded_choice)
        context = recorded_choice.context
        events = @event_store.read(
          @stream_factory.attempt(context.attempt_id),
          EventQueries::ATTEMPT_FOR_AGENT_CHOICE
        )
        state = Domain::Attempts::State.reduce(events.map { load(_1) })
        return state if state.absent?

        repository_matches = state.base_snapshots.any? do |snapshot|
          snapshot.repository_id == context.repository_id
        end
        valid = state.attempt_id == context.attempt_id &&
                state.change_set_id == context.change_set_id &&
                state.work_item_id == context.work_item_id &&
                repository_matches
        unless valid
          raise InvalidHistory.new(
            reason: "choice_attempt_scope_invalid",
            evidence: {
              choice_id: recorded_choice.choice_id,
              attempt_id: context.attempt_id
            }
          )
        end

        state
      end

      private

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
