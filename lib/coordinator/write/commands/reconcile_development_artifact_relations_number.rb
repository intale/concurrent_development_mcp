# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ReconcileDevelopmentArtifactRelationsNumber < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :statistics_id, Types::UuidV7
      attribute :source_event, EventReference
    end
  end
end
