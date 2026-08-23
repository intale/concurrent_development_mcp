# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactSurfaceDocumentV1 < Value
      SCHEMA = "candidate-impact-surface/v1"

      Transition = ImpactTransitionV1
      Observation = ImpactObservationV1
      Key = ImpactKeyV1
      Assumption = ImpactAssumptionV1

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :head_commit_oid, Types::GitOid
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :produces, Types::Array.of(Transition).constrained(max_size: 64)
      attribute :consumes, Types::Array.of(Observation).constrained(max_size: 64)
      attribute :may_affect, Types::Array.of(Key).constrained(max_size: 64)
      attribute :assumes, Types::Array.of(Assumption).constrained(max_size: 64)
    end
  end
end
