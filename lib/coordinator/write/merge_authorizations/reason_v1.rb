# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class ReasonV1 < Value
      attribute :code, Types::MergeAuthorizationReasonCode
      attribute :message, Types::String.constrained(min_size: 1, max_size: 500)
      attribute :candidate_id, Types::Identifier.optional
      attribute :work_item_id, Types::Identifier.optional
      attribute :dependency_id, Types::Identifier.optional
      attribute :source_candidate_id, Types::Identifier.optional
      attribute :target_candidate_id, Types::Identifier.optional
      attribute :obligation_id, Types::Identifier.optional
      attribute :obligation_status, Types::MergeAuthorizationObligationStatus.optional
      attribute :expected_reference, EventReference.optional
      attribute :observed_reference, EventReference.optional
      attribute :expected_digest, Types::Sha256Digest.optional
      attribute :observed_digest, Types::Sha256Digest.optional
      attribute :expected_oid, Types::GitOid.optional
      attribute :observed_oid, Types::GitOid.optional
    end
  end
end
