# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetCompletedV1 < Base
      Evidence = ChangeSetCompletions::WorkItemEvidenceV1

      contract type: "ChangeSetCompleted", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_completions,
                Types::Array.of(Evidence).constrained(min_size: 1, max_size: 100)
      attribute :release_set_completion_event, EventReference.optional
      attribute :rule_version, Types::String.enum("change-set-completion/v1")
      attribute :completed_at, Types::Timestamp
    end
  end
end
