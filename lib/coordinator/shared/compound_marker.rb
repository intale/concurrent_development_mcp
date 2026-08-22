# frozen_string_literal: true

module Coordinator::Shared
  class CompoundMarker < Value
    attribute :purpose, Types::MarkerPurpose
    attribute :components, Types::MarkerComponents
    attribute :digest, Types::Sha256Digest
    attribute :marker, Types::Marker
  end
end
