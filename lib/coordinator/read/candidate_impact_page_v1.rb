# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactPageV1 < Value
    attribute :candidate, CandidateSummaryV1
    attribute :impact_surface, CandidateImpactSurfaceViewV1.optional
    attribute :direction, Types::CandidateImpactQueryDirection
    attribute :relationships,
              Types::Array.of(CandidateImpactRelationshipV1).constrained(max_size: 100)
    attribute :next_global_position, Types::GlobalPosition.optional
    attribute :has_more, Types::Bool
  end
end
