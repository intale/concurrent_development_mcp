# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class CurrentImpactPolicyV1 < Value
      attribute :partition, Decisions::DecisionPartitionV1
      attribute :partition_event, EventReference.optional
      attribute :head, Decisions::DecisionHeadV1.optional
      attribute :definition_digest, Types::Sha256Digest.optional
      attribute :status, Types::MergeAuthorizationPolicyStatus
      attribute :required_evidence, Types::MergeAuthorizationRequiredEvidenceKinds
      attribute :valid_from, Types::Timestamp.optional

      def gating?
        %w[verification_gate merge_gate].include?(status)
      end
    end
  end
end
