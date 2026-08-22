# frozen_string_literal: true

module Coordinator::Read
  class ProjectionBarrier < Value
    attribute :stream_context, Types::Identifier
    attribute :stream_name, Types::Identifier
    attribute :stream_id, Types::Identifier
    attribute :stream_revision, Types::Integer.constrained(gteq: 0)
  end
end
