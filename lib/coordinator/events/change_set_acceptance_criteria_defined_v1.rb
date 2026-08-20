# frozen_string_literal: true

module Coordinator
  module Events
    class ChangeSetAcceptanceCriteriaDefinedV1 < Base
      contract type: "ChangeSetAcceptanceCriteriaDefined", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :acceptance_criteria, Types::AcceptanceCriteria
      attribute :defined_at, Types::Timestamp
    end
  end
end
