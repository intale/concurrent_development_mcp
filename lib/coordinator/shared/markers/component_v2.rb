# frozen_string_literal: true

module Coordinator::Shared
  module Markers
    class ComponentV2 < Value
      attribute :dimension, Types::MarkerDimension
      attribute :value, Types::CompoundMarkerValue
    end
  end
end
