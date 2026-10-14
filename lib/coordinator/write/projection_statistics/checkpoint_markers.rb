# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class CheckpointMarkers
    def initialize(codec: Coordinator::Shared::Markers::CodecV2.new)
      @codec = codec
    end

    def owner(change_set_id:, repository_id:)
      @codec.call(purpose: "change-set-repository-checkpoint-statistics", components: [
        { dimension: "change-set-id", value: change_set_id },
        { dimension: "repository-id", value: repository_id }
      ]).value!.marker
    end

    def candidate(candidate_id)
      "candidate-checkpoint-counted:#{candidate_id}"
    end

    def call(command_id:, change_set_id:, repository_id:)
      [ "command:#{command_id}", "change-set:#{change_set_id}", "repository:#{repository_id}" ]
    end
  end
end
