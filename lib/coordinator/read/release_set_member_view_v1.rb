# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetMemberViewV1 < Value
    attribute :position, Types::ReleaseSetMemberPosition
    attribute :repository_id, Types::RepositoryId
    attribute :merge_snapshot_id, Types::Identifier
    attribute :ordered_candidate_ids,
              Types::Array.of(Types::Identifier)
                .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
    attribute :authorization_event, Coordinator::Write::EventReference
  end
end
