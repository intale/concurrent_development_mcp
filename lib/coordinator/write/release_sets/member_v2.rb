# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class MemberV2 < Value
      attribute :position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :candidate_id, Types::Identifier
      attribute :candidate, Candidates::StateV2
    end
  end
end
