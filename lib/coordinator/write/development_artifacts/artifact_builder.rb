# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ArtifactBuilder
      def initialize(identity_builder: IdentityBuilder.new)
        @identity_builder = identity_builder
      end

      def call(scope:, title:, kind:, labels:, content:, source:)
        ArtifactV1.new(
          artifact_id: @identity_builder.call(content:),
          scope:,
          title:,
          kind:,
          labels: labels.uniq.sort_by(&:b),
          content:,
          source:
        )
      end
    end
  end
end
