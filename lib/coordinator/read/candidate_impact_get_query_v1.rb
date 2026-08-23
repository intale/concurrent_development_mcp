# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactGetQueryV1 < Value
    attribute :candidate_id, Types::Identifier
    attribute :direction, Types::CandidateImpactQueryDirection
    attribute :after_global_position, Types::GlobalPosition.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
