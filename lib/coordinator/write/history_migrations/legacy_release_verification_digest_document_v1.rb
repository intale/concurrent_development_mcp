# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyReleaseVerificationDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("release-set-verification/v1")
      attribute :release_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :attempt_number, Types::ReleaseSetVerificationAttemptNumber
      attribute :integration_events,
                Types::Array.of(EventReference)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :evidence, ReleaseSets::VerificationEvidenceV1
      attribute :policy_version, Types::ReleaseSetVerificationPolicyVersion
    end
  end
end
