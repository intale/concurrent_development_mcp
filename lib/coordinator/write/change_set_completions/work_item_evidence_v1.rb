# frozen_string_literal: true

module Coordinator::Write
  module ChangeSetCompletions
    class WorkItemEvidenceV1 < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :selected_event, EventReference
      attribute :completed_event, EventReference
      attribute :completed_at, Types::Timestamp
    end
  end
end
