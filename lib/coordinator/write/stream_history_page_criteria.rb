# frozen_string_literal: true

module Coordinator::Write
  class StreamHistoryPageCriteria < Value
    attribute :event_types, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 100)
    attribute :from_revision, Types::Integer.constrained(gteq: 0)
    attribute :to_revision, Types::Integer.constrained(gteq: 0)
    attribute :page_size, Types::Integer.constrained(gteq: 1, lteq: 1000)
  end
end
