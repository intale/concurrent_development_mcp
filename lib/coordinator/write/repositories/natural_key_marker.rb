# frozen_string_literal: true

module Coordinator::Write
  module Repositories
    class NaturalKeyMarker
      def initialize(compound_marker_builder: Coordinator::Shared::CompoundMarkerBuilder.new)
        @compound_marker_builder = compound_marker_builder
      end

      def call(scope:, repository_key:)
        @compound_marker_builder.call(
          Coordinator::Shared::CompoundMarkerDefinitionV1.new(
            purpose: "scoped-repository-key",
            components: [ "scope:#{scope}", "repository-key:#{repository_key}" ]
          )
        )
      end
    end
  end
end
