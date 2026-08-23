# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactSurfaceV1 < Value
      Transition = ImpactTransitionV1
      Observation = ImpactObservationV1
      Key = ImpactKeyV1
      Assumption = ImpactAssumptionV1

      attribute :policy_version, Types::String.enum(ImpactSurfaceDocumentV1::SCHEMA)
      attribute :digest, Types::Sha256Digest
      attribute :produces, Types::Array.of(Transition).constrained(max_size: 64)
      attribute :consumes, Types::Array.of(Observation).constrained(max_size: 64)
      attribute :may_affect, Types::Array.of(Key).constrained(max_size: 64)
      attribute :assumes, Types::Array.of(Assumption).constrained(max_size: 64)
      attribute :analyzer, ImpactAnalyzerV1
    end
  end
end
