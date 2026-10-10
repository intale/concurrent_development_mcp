# frozen_string_literal: true

module Coordinator::Read::Search
  class Page < Coordinator::Read::Value
    attribute :items, Coordinator::Read::Types::Array.of(Document).constrained(max_size: Limits::PAGE)
    attribute :has_more, Coordinator::Read::Types::Bool
    attribute :cursor, Coordinator::Read::Types::String.optional
  end
end
