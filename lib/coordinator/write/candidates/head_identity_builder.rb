# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class HeadIdentityBuilder
      def initialize(
        id_generator: IdGenerator.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @id_generator = id_generator
        @compound_marker_builder = compound_marker_builder
      end

      def call(repository_id:, object_format:, head_commit_oid:)
        document = HeadIdentityDocumentV1.new(
          schema: HeadIdentityDocumentV1::SCHEMA,
          repository_id:,
          object_format:,
          head_commit_oid:
        )
        marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-head-identity",
            components: [
              "repository:#{repository_id}",
              "object-format:#{object_format}",
              "head-commit-oid:#{head_commit_oid}"
            ]
          )
        )

        HeadIdentityV1.new(
          document:,
          registry_id: @id_generator.uuid_v7,
          marker: marker.marker
        )
      end
    end
  end
end
