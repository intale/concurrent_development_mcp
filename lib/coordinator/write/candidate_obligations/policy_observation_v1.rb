# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class PolicyObservationV1 < Value
      attribute :status, Types::CandidateObligationPolicyStatus
      attribute :evidence, ImpactPolicyEvidenceV1.optional

      def self.stale
        new(status: "stale", evidence: nil)
      end

      def self.non_gating
        new(status: "non_gating", evidence: nil)
      end

      def self.inactive
        new(status: "inactive", evidence: nil)
      end

      def self.gating(evidence)
        new(status: "gating", evidence:)
      end
    end
  end
end
