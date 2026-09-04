# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetPreparationViewV2 < Value
    attribute :release_set_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :ordered_members,
              Types::Array.of(ReleaseSetMemberViewV1)
                .constrained(
                  min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                  max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                )
    attribute :release_digest, Types::Sha256Digest
    attribute :policy_version, Types::ReleaseSetPreparationPolicyVersion
  end
end
