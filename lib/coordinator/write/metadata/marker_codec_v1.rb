# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class MarkerCodecV1 < EventMetadata
      attribute :marker_codec_version, Types::Identifier
    end
  end
end
