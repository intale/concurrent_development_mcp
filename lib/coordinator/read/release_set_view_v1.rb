# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetViewV1 < Value
    Member = ReleaseSetMemberViewV1
    Integration = ReleaseSetIntegrationViewV1
    Verification = ReleaseSetVerificationViewV1
    Activation = ReleaseSetActivationViewV1
    CompensationRequest = ReleaseSetCompensationRequestViewV1
    Completion = ReleaseSetCompletionViewV1

    attribute :release_set_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :ordered_members,
              Types::Array.of(Member)
                .constrained(
                  min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                  max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                )
    attribute :release_digest, Types::Sha256Digest
    attribute :status,
              Types::String.enum(
                "prepared", "integrating", "verifying", "verified", "activated",
                "compensation_requested", "completed"
              )
    attribute :verification_status, Types::String.enum("unverified", "failed", "passed")
    attribute :integrations,
              Types::Array.of(Integration)
                .constrained(
                  max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS *
                    Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
                )
    attribute :verifications,
              Types::Array.of(Verification)
                .constrained(max_size: Types::RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS)
    attribute? :activation, Activation.optional
    attribute? :compensation_request, CompensationRequest.optional
    attribute? :completion, Completion.optional
    attribute :preparation_policy_version, Types::ReleaseSetPreparationPolicyVersion
    attribute :prepared_at, Types::Timestamp
    attribute :prepared, ReleaseSetSourceEvidenceV1
  end
end
