# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetMemberAddedV1 < Base
      contract type: "ReleaseSetMemberAdded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :repository_id, Types::RepositoryId
      attribute :candidate_id, Types::Identifier
    end
  end
end
