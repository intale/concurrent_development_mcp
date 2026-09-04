# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemAcceptanceCriteriaDefinedV1 < Base
      contract type: "WorkItemAcceptanceCriteriaDefined", version: 1

      attribute :work_item_id, Types::Identifier
      attribute :acceptance_criteria, Types::WorkItemAcceptanceCriteria
    end
  end
end
