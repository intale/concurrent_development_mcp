# frozen_string_literal: true

module Coordinator::Read::Search
  class Filters < Coordinator::Read::Value
    attribute :scope, Coordinator::Read::Types::String.optional
    attribute :repository_id, Coordinator::Read::Types::String.optional
    attribute :entity_types, Coordinator::Read::Types::Array.of(Coordinator::Read::Types::String)
  end
end
