# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ImpactPolicyEvidenceV1 < Value
      attribute :partition_event, EventReference
      attribute :partition, Decisions::DecisionPartitionV1
      attribute :head, Decisions::DecisionHeadV1
      attribute :definition_digest, Types::Sha256Digest
      attribute :change_set_id, Types::Identifier
      attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
      attribute :enforcement, Types::CandidateImpactPolicyEnforcementLevel
      attribute :valid_from, Types::Timestamp
    end
  end
end
