# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyReleaseDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("release-set/v1")
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :ordered_members,
                Types::Array.of(ReleaseSets::MemberEvidenceV1)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :policy_version, Types::ReleaseSetPreparationPolicyVersion
    end
  end
end
