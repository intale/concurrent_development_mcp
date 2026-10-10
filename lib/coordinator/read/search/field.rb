# frozen_string_literal: true

module Coordinator::Read::Search
  class Field < Coordinator::Read::Value
    attribute :selector, Coordinator::Read::Types::String
    attribute :entity_type, Coordinator::Read::Types::String
    attribute :source, Coordinator::Read::Types::String
    attribute :column, Coordinator::Read::Types::String
    attribute :path, Coordinator::Read::Types::Array.of(Coordinator::Read::Types::String)
    attribute :values, Coordinator::Read::Types::String.enum("scalar", "elements", "strings")
    attribute :retrieval_tool, Coordinator::Read::Types::String
  end
end
