# frozen_string_literal: true

module Coordinator
  class EventReference < Value
    attribute :event_id, Types::UuidV7
    attribute :type, Types::Identifier
    attribute :stream_context, Types::Identifier
    attribute :stream_name, Types::Identifier
    attribute :stream_id, Types::Identifier
    attribute :stream_revision, Types::Integer.constrained(gteq: 0)
  end
end
