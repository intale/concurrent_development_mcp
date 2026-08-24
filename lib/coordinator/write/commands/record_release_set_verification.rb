# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordReleaseSetVerification < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
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
