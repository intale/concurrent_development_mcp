# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class MemberV2 < Value
      attribute :position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :merge_snapshot_id, Types::Identifier
      attribute :ordered_candidate_ids,
                Types::Array.of(Types::Identifier)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :authorization_event, EventReference
      attribute :ordered_candidates,
                Types::Array.of(Candidates::StateV2)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
    end
  end
end
