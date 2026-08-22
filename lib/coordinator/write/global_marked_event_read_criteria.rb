# frozen_string_literal: true

module Coordinator::Write
  class GlobalMarkedEventReadCriteria < Value
    attribute :stream_context, Types::Identifier
    attribute :stream_name, Types::Identifier
    attribute :event_types, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 10)
    attribute :marker, Types::Marker
    attribute :maximum_count, Types::Integer.constrained(gteq: 1)
    attribute :direction, Types::Symbol.enum(:asc, :desc)

    def query_max_count
      maximum_count + 1
    end
  end
end
