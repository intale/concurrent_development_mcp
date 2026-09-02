# frozen_string_literal: true

module Coordinator::Shared
  module Markers
    class DefinitionV2 < Value
      attribute :purpose, Types::MarkerPurpose
      attribute :components,
                Types::Array.of(Types.Instance(ComponentV2)).constrained(
                  min_size: 1,
                  max_size: Types::COMPOUND_MARKER_MAXIMUM_COMPONENTS
                )
    end
  end
end
