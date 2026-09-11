# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetMemberAddedV1 < Base
      contract type: "ReleaseSetMemberAdded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :merge_snapshot_id, Types::Identifier
      attribute :ordered_candidate_ids,
                Types::Array.of(Types::Identifier)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :authorization_event, EventReference
    end
  end
end
