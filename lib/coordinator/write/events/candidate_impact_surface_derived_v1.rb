# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactSurfaceDerivedV1 < Base
      Transition = Candidates::ImpactTransitionV1
      Observation = Candidates::ImpactObservationV1
      Key = Candidates::ImpactKeyV1
      Assumption = Candidates::ImpactAssumptionV1

      contract type: "CandidateImpactSurfaceDerived", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :policy_version, Types::String.enum(Candidates::ImpactSurfaceDocumentV1::SCHEMA)
      attribute :surface_digest, Types::Sha256Digest
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :produces, Types::Array.of(Transition).constrained(max_size: 64)
      attribute :consumes, Types::Array.of(Observation).constrained(max_size: 64)
      attribute :may_affect, Types::Array.of(Key).constrained(max_size: 64)
      attribute :assumes, Types::Array.of(Assumption).constrained(max_size: 64)
      attribute :analyzer, Candidates::ImpactAnalyzerV1
      attribute :evidence_status, Types::CandidateEvidenceStatus
      attribute :derived_at, Types::Timestamp
    end
  end
end
