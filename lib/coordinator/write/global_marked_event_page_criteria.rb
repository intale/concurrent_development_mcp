# frozen_string_literal: true

module Coordinator::Write
  class GlobalMarkedEventPageCriteria < Value
    attribute :stream_context, Types::Identifier
    attribute :stream_name, Types::Identifier
    attribute :event_type, Types::Identifier
    attribute :markers, Types::Array.of(Types::ResourceMarker).constrained(min_size: 1, max_size: 32)
    attribute :from_position, Types::Integer.constrained(gteq: 0)
    attribute :to_position, Types::Integer.constrained(gteq: 0)
    attribute :page_size, Types::Integer.constrained(gteq: 1, lteq: 4_096)
    attribute :direction, Types::Symbol.enum(:asc, :desc)

    def query_max_count
      page_size + 1
    end
  end
end
