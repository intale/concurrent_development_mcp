# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class MetricDefinition < Value
      attribute :key, Types::Symbol
      attribute :name, Types::String
      attribute :kind, Types::Symbol.enum(:counter, :histogram, :up_down_counter, :observable_gauge)
      attribute :unit, Types::String
      attribute :description, Types::String
      attribute :dimensions, Types::Array.of(Types::String)
      attribute :boundaries, Types::Array.of(Types::Float).default([].freeze)
    end
  end
end
