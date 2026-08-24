# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetPreparedV1 < Base
      Member = ReleaseSets::MemberEvidenceV1

      contract type: "ReleaseSetPrepared", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :ordered_members,
                Types::Array.of(Member)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :release_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetPreparationPolicyVersion
      attribute :prepared_at, Types::Timestamp
    end
  end
end
