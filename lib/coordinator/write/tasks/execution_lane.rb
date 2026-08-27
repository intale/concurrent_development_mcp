# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class ExecutionLane
      COUNT = 2
      MARKER_PREFIX = "task-execution-lane:v1:"

      def initialize(canonical_json: Coordinator::Shared::CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def index(command_id)
        digest = @canonical_json.sha256(
          { "schema" => "coordination-task-execution-lane/v1", "command_id" => command_id }
        )

        digest.delete_prefix("sha256:").first(8).to_i(16).modulo(COUNT)
      end

      def marker(command_id)
        marker_for(index(command_id))
      end

      def marker_for(index)
        "#{MARKER_PREFIX}#{index}"
      end
    end
  end
end
