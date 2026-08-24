# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetViewV1 < Value
    Member = Coordinator::Write::ReleaseSets::MemberEvidenceV1

    attribute :release_set_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :ordered_members,
              Types::Array.of(Member)
                .constrained(
                  min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                  max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                )
    attribute :release_digest, Types::Sha256Digest
    attribute :status, Types::String.enum("prepared")
    attribute :preparation_policy_version, Types::ReleaseSetPreparationPolicyVersion
    attribute :prepared_at, Types::Timestamp
    attribute :prepared, ReleaseSetSourceEvidenceV1
  end
end
