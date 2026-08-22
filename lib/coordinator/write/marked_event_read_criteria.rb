# frozen_string_literal: true

module Coordinator::Write
  class MarkedEventReadCriteria < Value
    attribute :event_type, Types::Identifier
    attribute :marker, Types::Marker
    attribute :maximum_count, Types::Integer.constrained(gteq: 1)
    attribute :direction, Types::Symbol.enum(:asc, :desc)

    def query_max_count
      maximum_count + 1
    end
  end
end
