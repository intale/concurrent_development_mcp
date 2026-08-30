# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RollResourceBoundaryEpoch < Value
      attribute :command_id, Types::InternalCommandId
      attribute :actor, Actor
      attribute :repository_id, Types::RepositoryId
      attribute :boundary_marker, Types::ResourceMarker
      attribute :source_event_id, Types::UuidV7
      attribute :source_global_position, Types::GlobalPosition
    end
  end
end
