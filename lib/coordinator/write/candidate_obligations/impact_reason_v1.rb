# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ImpactReasonV1 < Value
      attribute :kind, Types::CandidateImpactReasonKind
      attribute :matches, Types::CandidateImpactReasonMatches
      attribute :source_evidence, EventReference
      attribute :target_evidence, EventReference
    end
  end
end
