# frozen_string_literal: true

module Coordinator::Read::Search
  class Query < Coordinator::Read::Value
    attribute :fields, Coordinator::Read::Types::Array.of(Branch)
    attribute :filters, Filters
    attribute :limit, Coordinator::Read::Types::Integer
    attribute :fingerprint, Coordinator::Read::Types::String
    attribute :boundary, CursorBoundary.optional
  end
end
