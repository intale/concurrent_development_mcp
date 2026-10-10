# frozen_string_literal: true

module Coordinator::Read::Search
  class SqlFragment < Coordinator::Read::Value
    attribute :sql, Coordinator::Read::Types::String
    attribute :binds, Coordinator::Read::Types::Array.of(Coordinator::Read::Types::String)
  end
end
