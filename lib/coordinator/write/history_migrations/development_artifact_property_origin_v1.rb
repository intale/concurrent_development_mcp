# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DevelopmentArtifactPropertyOriginV1 < Value
      attribute :role, Types::Identifier
      attribute :event_type, Types::Identifier
      attribute :step_name, Types::Identifier
      attribute :source_event, EventReference
    end
  end
end
