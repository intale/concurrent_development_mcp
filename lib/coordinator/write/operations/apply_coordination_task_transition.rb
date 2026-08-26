# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ApplyCoordinationTaskTransition
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        loader: Tasks::Loader.new(event_store:),
        stream_factory: StreamFactory.new,
        event_factory: EventFactory.new,
        id_generator: IdGenerator.new,
        revision_guard: ExpectedRevisionGuard.new
      )
        @event_store = event_store
        @loader = loader
        @stream_factory = stream_factory
        @event_factory = event_factory
        @id_generator = id_generator
        @revision_guard = revision_guard
      end

      def call(command:, decider:, transition_name:, caused_by: nil)
        event_id = @id_generator.uuid_v7

        @revision_guard.call(task_id: command.task_id) do
          snapshot = @loader.call(command.task_id)
          decision = decider.call(state: snapshot.state, command:)
          next decision if decision.failure?

          event = decision.value!
          next Success(snapshot.state) unless event

          append(
            event:,
            snapshot:,
            transition_name:,
            event_id:,
            caused_by: caused_by || snapshot.persisted_events.first
          )
          Success(snapshot.state.apply(event))
        end
      end

      private

      def append(event:, snapshot:, transition_name:, event_id:, caused_by:)
        task_id = event.task_id
        persisted = @event_factory.build!(
          event:,
          event_id:,
          metadata: EventMetadata.new(
            command_id: "task:#{task_id}:#{transition_name}",
            actor_kind: "system",
            actor_id: "coordinator",
            recorded_by: "coordinator",
            policy_version: "coordination-task/v1"
          ),
          markers: [ "task:#{task_id}" ],
          caused_by:
        )

        @event_store.append(
          @stream_factory.coordination_task(task_id),
          [ persisted ],
          expected_revision: snapshot.latest_revision
        )
      end
    end
  end
end
