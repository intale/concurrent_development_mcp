# frozen_string_literal: true

module Coordinator::Write
  class LatestEventReadCriteria < Value
    attribute :event_types, Types::Array.of(Types::String).constrained(min_size: 1, max_size: 100)
  end
end
