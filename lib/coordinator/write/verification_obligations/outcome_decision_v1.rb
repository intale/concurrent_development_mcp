# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class OutcomeDecisionV1 < Value
      Observation = Types.Instance(CompatibilityAssessments::EvidenceObservationV2)

      attribute :kind, Types::String.enum("none", "satisfied", "failed")
      attribute :selected_evidence, Types::Array.of(Observation).constrained(max_size: 8)

      def terminal? = kind != "none"

      def self.none = new(kind: "none", selected_evidence: [])
      def self.satisfied(evidence) = new(kind: "satisfied", selected_evidence: evidence)
      def self.failed(evidence) = new(kind: "failed", selected_evidence: [ evidence ])
    end
  end
end
