# frozen_string_literal: true

module Coordinator::Write
  class GroupedEventReadCriteria < Value
    attribute :event_types, Types::Array.of(Types::String).constrained(min_size: 1)
    attribute :direction, Types::Symbol.enum(:asc, :desc)
  end
end
