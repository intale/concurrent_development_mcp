# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteInitializeProjectionFacts
      include Dry::Monads[:result]
      MAXIMUM_ATTEMPTS = 3

      def initialize(event_store:, loader: ProjectionInitialization::SourceLoader.new(event_store:),
        decider: Domain::ProjectionInitialization::InitializeFacts.new, event_factory: EventFactory.new,
        id_generator: IdGenerator.new)
        @event_store, @loader, @decider, @event_factory, @id_generator = event_store, loader, decider, event_factory, id_generator
      end

      def call_command(command)
        attempts = 0
        begin
          attempts += 1
          state = @loader.call(command.source_event)
          unless state
            return Failure(OutcomeError.new(code: :projection_initialization_source_invalid,
              message: "Initialization requires an exact modeled owner fact", details: { source_event: command.source_event.to_h }))
          end
          emissions = @decider.call(command:, state:)
          return Success([]) if emissions.empty?

          events = emissions.map do |emission|
            @event_factory.build!(event: emission.event, event_id: @id_generator.uuid_v7,
              metadata: emission.metadata, markers: [ "command:#{command.command_id}", "projection-initialization:#{state.source.id}" ],
              caused_by: state.source, correlation_id: state.source.correlation_id)
          end
          Success(@event_store.append(state.stream, events, expected_revision: state.latest_revision))
        rescue PgEventstore::WrongExpectedRevisionError
          retry if attempts < MAXIMUM_ATTEMPTS

          Failure(OutcomeError.new(code: :projection_initialization_concurrency_conflict,
            message: "Initialization raced with another write; the request may succeed if retried",
            details: { source_event: command.source_event.to_h, attempts:, retryable: true }))
        end
      end
    end
  end
end
