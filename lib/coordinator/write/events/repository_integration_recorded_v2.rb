# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryIntegrationRecordedV2 < Base
      contract type: "RepositoryIntegrationRecorded", version: 2

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :attempt_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetIntegrationAttemptNumber
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :failure, ReleaseSets::IntegrationFailureV2.optional
    end
  end
end
