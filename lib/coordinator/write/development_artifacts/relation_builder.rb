# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationBuilder
      def initialize(identity_builder: RelationIdentityBuilder.new)
        @identity_builder = identity_builder
      end

      def call(source_artifact_id:, relation:, target:, attributes:)
        RelationV1.new(
          relation_id: @identity_builder.call(
            source_artifact_id:,
            relation:,
            target:,
            attributes:
          ),
          source_artifact_id:,
          relation:,
          target:,
          attributes:
        )
      end
    end
  end
end
