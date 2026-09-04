# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class IntegrationFactV2 < Value
      attribute :payload, Events::RepositoryIntegrationRecordedV2
      attribute :event, EventReference
      attribute :merge_observation, EventReference.optional
      attribute :merge_link_event, EventReference.optional
      attribute :integration_digest, Types::Sha256Digest
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :release_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetIntegrationPolicyVersion
    end
  end
end
