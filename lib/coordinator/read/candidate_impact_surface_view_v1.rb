# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactSurfaceViewV1 < Value
    attribute :policy_version, Types::String.enum("candidate-impact-surface/v1")
    attribute :surface_digest, Types::Sha256Digest
    attribute :evidence_revision, Types::CandidateEvidenceRevision
    attribute :manifest_digest, Types::Sha256Digest
    attribute :build_context_digest, Types::Sha256Digest.optional
    attribute :produces,
              Types::Array.of(Coordinator::Write::Candidates::ImpactTransitionV1).constrained(max_size: 64)
    attribute :consumes,
              Types::Array.of(Coordinator::Write::Candidates::ImpactObservationV1).constrained(max_size: 64)
    attribute :may_affect,
              Types::Array.of(Coordinator::Write::Candidates::ImpactKeyV1).constrained(max_size: 64)
    attribute :assumes,
              Types::Array.of(Coordinator::Write::Candidates::ImpactAssumptionV1).constrained(max_size: 64)
    attribute :analyzer, Coordinator::Write::Candidates::ImpactAnalyzerV1
    attribute :evidence_status, Types::CandidateEvidenceStatus
    attribute :evidence, CandidateSourceEvidenceV1
  end
end
