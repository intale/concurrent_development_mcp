# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactMigrationContextV1 < Value
      attribute :artifact_stream, StreamReference
      attribute :artifact_id, Types::UuidV7
      attribute :observation_stream, StreamReference.optional
      attribute :observation_id, Types::UuidV7.optional
      attribute :state, DevelopmentArtifactSourceStateV1
    end
  end
end
