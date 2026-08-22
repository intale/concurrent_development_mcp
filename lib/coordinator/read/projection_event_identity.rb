# frozen_string_literal: true

module Coordinator::Read
  class ProjectionEventIdentity < Value
    attribute :stream_context, Types::Identifier
    attribute :stream_name, Types::Identifier
    attribute :stream_id, Types::Identifier
    attribute :stream_revision, Types::Integer.constrained(gteq: 0)
    attribute :event_id, Types::UuidV7
    attribute :event_type, Types::Identifier
    attribute :command_id, Types::Identifier.optional

    def self.from_event(event)
      new(
        stream_context: event.stream.context,
        stream_name: event.stream.stream_name,
        stream_id: event.stream.stream_id,
        stream_revision: event.stream_revision,
        event_id: event.id,
        event_type: event.type,
        command_id: event.metadata["command_id"]
      )
    end

    def barrier
      ProjectionBarrier.new(
        stream_context:,
        stream_name:,
        stream_id:,
        stream_revision:
      )
    end
  end
end
