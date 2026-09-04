# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactSurfaceAssignedV1 < Base
      contract type: "CandidateImpactSurfaceAssigned", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :surface_id, Types::UuidV7
    end
  end
end
