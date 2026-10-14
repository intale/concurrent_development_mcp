# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class EnsureDevelopmentArtifactRelationStatistics < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :statistics_id, Types::UuidV7
    end
  end
end
