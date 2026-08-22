# frozen_string_literal: true

module Coordinator::Shared
  class CompoundMarkerDefinitionV1 < Value
    attribute :purpose, Types::MarkerPurpose
    attribute :components, Types::MarkerComponents
  end
end
