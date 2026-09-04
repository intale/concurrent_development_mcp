# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class IntegrationDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("release-set-integration/v1")
      attribute :release_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :attempt_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetIntegrationAttemptNumber
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :merge_observation_event, EventReference.optional
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :failure, IntegrationFailureV2.optional
      attribute :policy_version, Types::ReleaseSetIntegrationPolicyVersion
    end
  end
end
