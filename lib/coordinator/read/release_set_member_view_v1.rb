# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetMemberViewV1 < Value
    attribute :position, Types::ReleaseSetMemberPosition
    attribute :repository_id, Types::RepositoryId
    attribute :candidate_id, Types::Identifier
  end
end
