# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class WorkItemProgressV1 < Value
      Dependency = DependencyProgressV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :selected_event, EventReference
      attribute :completed_event, EventReference
      attribute :incoming_dependencies,
                Types::Array.of(Dependency).constrained(max_size: 500)
    end
  end
end
