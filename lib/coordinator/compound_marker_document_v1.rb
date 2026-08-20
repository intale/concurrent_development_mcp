# frozen_string_literal: true

module Coordinator
  class CompoundMarkerDocumentV1 < Value
    attribute :schema, Types::String.enum("coordinator-compound-marker/v1")
    attribute :purpose, Types::MarkerPurpose
    attribute :components, Types::MarkerComponents
  end
end
