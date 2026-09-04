# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class MemberSummaryV2 < Value
      attribute :position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :candidate_id, Types::Identifier
    end
  end
end
