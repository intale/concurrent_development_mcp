# frozen_string_literal: true

module Coordinator::Processes::ProcessManagers
  class ProjectionInitialization
    ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "projection-initialization")

    def initialize(operation:)
      @operation = operation
    end

    def call(event)
      reference = Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
        stream_context: event.stream.context, stream_name: event.stream.stream_name,
        stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
      result = @operation.call_command(Coordinator::Write::Commands::InitializeProjectionFacts.new(
        command_id: "projection-initialization:#{event.id}", actor: ACTOR, source_event: reference))
      raise result.failure.message if result.failure?

      nil
    end
  end
end
