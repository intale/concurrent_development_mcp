# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAssignedToRepositoryV1 < Base
      contract type: "WorkItemAssignedToRepository", version: 1

      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
    end
  end
end
