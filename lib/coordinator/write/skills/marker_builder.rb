# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class MarkerBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(identity:, command_id:)
        [
          "skill:#{identity.skill_id}",
          dimension_marker("name", identity.name),
          dimension_marker("scope", identity.scope),
          "command:#{command_id}"
        ].freeze
      end

      private

      def dimension_marker(dimension, value)
        digest = @canonical_json.sha256(
          schema: "skill-marker/v1",
          dimension:,
          value:
        ).delete_prefix("sha256:")
        "skill-#{dimension}:v1:#{digest}"
      end
    end
  end
end
