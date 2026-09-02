# frozen_string_literal: true

module Coordinator::Shared
  module Markers
    class EncodedV2 < Value
      attribute :definition, Types.Instance(DefinitionV2)
      attribute :marker, Types::ResourceMarker
    end
  end
end
