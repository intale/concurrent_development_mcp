# frozen_string_literal: true

module Coordinator::Write
  class EventReadCriteria < Value
    attribute :event_types, Types::Array.of(Types::String).constrained(min_size: 1)
    attribute :maximum_count, Types::Integer.constrained(gteq: 1)
    attribute :direction, Types::Symbol.enum(:asc, :desc)
    attribute? :from_revision, Types::StreamRevision.optional.default(nil)
    attribute? :to_revision, Types::StreamRevision.optional.default(nil)

    def query_max_count
      maximum_count + 1
    end
  end
end
