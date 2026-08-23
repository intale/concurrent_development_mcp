# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactPolicySummaryV1 < Value
    attribute :change_set_id, Types::Identifier
    attribute :partition, Coordinator::Write::Decisions::DecisionPartitionV1
    attribute :head, Coordinator::Write::Decisions::DecisionHeadV1
    attribute :definition_digest, Types::Sha256Digest
    attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
    attribute :enforcement, Types::CandidateImpactPolicyEnforcementLevel
    attribute :valid_from, Types::Timestamp
    attribute :evidence, CandidateImpactPolicyEvidenceV1
  end
end
