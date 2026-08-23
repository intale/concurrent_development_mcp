# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactTransitionV1 < Value
      attribute :impact_key, Types::CandidateImpactKey
      attribute :before, Types::CandidateImpactValue.optional
      attribute :after, Types::CandidateImpactValue
    end
  end
end
