# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactObservationV1 < Value
      attribute :impact_key, Types::CandidateImpactKey
      attribute :value, Types::CandidateImpactValue
    end
  end
end
