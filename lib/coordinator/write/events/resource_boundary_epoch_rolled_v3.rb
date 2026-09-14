# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceBoundaryEpochRolledV3 < Base
      contract type: "ResourceBoundaryEpochRolled", version: 3

      attribute :repository_id, Types::RepositoryId
      attribute :boundary_marker, Types::ResourceMarker
      attribute :epoch, Types::Integer.constrained(gteq: 1)
      attribute :through_global_position, Types::GlobalPosition
    end
  end
end
