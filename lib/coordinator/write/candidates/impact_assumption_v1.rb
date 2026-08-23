# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactAssumptionV1 < Value
      attribute :impact_key, Types::CandidateImpactKey
      attribute :predicate, Types::CandidateImpactValue
    end
  end
end
