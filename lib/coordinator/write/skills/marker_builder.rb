# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class MarkerBuilder
      NATURAL_KEY_PURPOSE = "skill-natural-key"

      def initialize(marker_codec: Coordinator::Shared::Markers::CodecV2.new)
        @marker_codec = marker_codec
      end

      def call(identity:, command_id:, register_natural_key: false)
        markers = [
          "skill:#{identity.skill_id}",
          "command:#{command_id}"
        ]
        markers << natural_key(name: identity.name, scope: identity.scope) if register_natural_key
        markers.freeze
      end

      def natural_key(name:, scope:)
        result = @marker_codec.call(
          purpose: NATURAL_KEY_PURPOSE,
          components: [
            { dimension: "name", value: name },
            { dimension: "scope", value: scope }
          ]
        )
        raise ArgumentError, "Skill natural key is invalid: #{result.failure.errors.inspect}" if result.failure?

        result.value!.marker
      end
    end
  end
end
