# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceRecordedV2 < Base
      contract type: "AgentChoiceRecorded", version: 2

      Option = AgentChoices::ChoiceOptionV1

      attribute :choice_id, Types::Identifier
      attribute :choice_type, Types::AgentChoiceType
      attribute :selected, Option
      attribute :alternatives, Types::Array.of(Option).constrained(max_size: 10)
      attribute :context, DecisionContexts::QueryContextV1
      attribute :decision_context, DecisionContexts::ContextV1
      attribute :reason_summary, Types::String.constrained(min_size: 1, max_size: 4_000)
    end
  end
end
