# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactContextV1 < Value
      attribute :assessment_stream, StreamReference
      attribute :choice_stream, StreamReference
      attribute :assessment_id, Types::UuidV7
      attribute :choice_id, Types::UuidV7
      attribute :attempt_id, Types::UuidV7
      attribute :choice_type, Types::AgentChoiceType
      attribute :accepted_choice, EventReference
      attribute :decision_change, EventReference
      attribute :before_context, DecisionContexts::ContextV1
      attribute :after_context, DecisionContexts::ContextV1
      attribute :assessment, AgentChoiceImpacts::ImpactAssessmentV2
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    end
  end
end
