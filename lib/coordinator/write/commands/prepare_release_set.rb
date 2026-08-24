# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class PrepareReleaseSet < Value
      Member = ReleaseSets::RequestedMemberV1

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :release_set_id, Types::Identifier
      attribute :ordered_members,
                Types::Array.of(Member)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :policy_version, Types::ReleaseSetPreparationPolicyVersion
    end
  end
end
