# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactSurfaceDerivedV2 < Base
      Transition = Candidates::ImpactTransitionV1
      Observation = Candidates::ImpactObservationV1
      Key = Candidates::ImpactKeyV1
      Assumption = Candidates::ImpactAssumptionV1

      contract type: "CandidateImpactSurfaceDerived", version: 2

      attribute :surface_id, Types::UuidV7
      attribute :candidate_id, Types::Identifier
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :produces, Types::Array.of(Transition).constrained(max_size: 64)
      attribute :consumes, Types::Array.of(Observation).constrained(max_size: 64)
      attribute :may_affect, Types::Array.of(Key).constrained(max_size: 64)
      attribute :assumes, Types::Array.of(Assumption).constrained(max_size: 64)
    end
  end
end
