# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CollectorV1 < EventMetadata
      attribute :collector, Types::DevelopmentArtifactCollector
    end
  end
end
