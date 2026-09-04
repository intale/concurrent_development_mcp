# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetAcceptanceCriteriaDefinedV2 < Base
      contract type: "ChangeSetAcceptanceCriteriaDefined", version: 2

      attribute :change_set_id, Types::Identifier
      attribute :acceptance_criteria, Types::AcceptanceCriteria
    end
  end
end
