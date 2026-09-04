# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class VerificationFactV2 < Value
      attribute :payload, Events::ReleaseSetVerificationRecordedV2
      attribute :event, EventReference
      attribute :integration_events,
                Types::Array.of(EventReference)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :integration_link_events,
                Types::Array.of(EventReference)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :release_digest, Types::Sha256Digest
      attribute :verification_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetVerificationPolicyVersion
    end
  end
end
