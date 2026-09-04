# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordRepositoryIntegration < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :attempt_id, Types::Identifier
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :merge_observation_event, EventReference.optional
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :failure, ReleaseSets::IntegrationFailureV2.optional
      attribute :policy_version, Types::ReleaseSetIntegrationPolicyVersion
    end
  end
end
