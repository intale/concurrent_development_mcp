# frozen_string_literal: true

module Coordinator::Read::Search
  class Source < Coordinator::Read::Value
    attribute :table, Coordinator::Read::Types::String
    attribute :from, Coordinator::Read::Types::String
    attribute :row_id, Coordinator::Read::Types::String
    attribute :identity, Coordinator::Read::Types::String
    attribute :entity_id, Coordinator::Read::Types::String
    attribute :updated_at, Coordinator::Read::Types::String
    attribute :scope, Coordinator::Read::Types::String
    attribute :repository_id, Coordinator::Read::Types::String
    attribute :membership, Coordinator::Read::Types::String
    attribute :direct_scope, Coordinator::Read::Types::Bool
    attribute :value, Coordinator::Read::Types::String
    attribute :path, Coordinator::Read::Types::String
    attribute :condition, Coordinator::Read::Types::String
    attribute :multiple_values, Coordinator::Read::Types::Bool
    attribute :retrieval, Coordinator::Read::Types::String
    attribute :provenance, Coordinator::Read::Types::String
  end
end
