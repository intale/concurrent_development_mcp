# frozen_string_literal: true

module Coordinator::Write
  module CommandLifecycle
    class RequestMarker
      def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
        @compound_marker_builder = compound_marker_builder
      end

      def call(actor:, request_id:)
        @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "command-request",
            components: [
              "actor-kind:#{actor.kind}",
              "actor-id:#{actor.id}",
              "request-id:#{request_id}"
            ]
          )
        ).marker
      end
    end
  end
end
