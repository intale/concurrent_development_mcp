# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ReleaseDigestDocumentV1 < Value
      Member = MemberEvidenceV1

      attribute :schema, Types::String.enum("release-set/v1")
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
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
