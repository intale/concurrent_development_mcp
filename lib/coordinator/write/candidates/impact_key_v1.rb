# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactKeyV1 < Value
      attribute :impact_key, Types::CandidateImpactKey
    end
  end
end
