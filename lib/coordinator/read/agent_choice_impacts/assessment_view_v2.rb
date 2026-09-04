# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class AssessmentViewV2 < Value
      attribute :assessment_id, Types::UuidV7
      attribute :choice_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :assessment, Coordinator::Write::AgentChoiceImpacts::ImpactAssessmentV2
      attribute :accepted_choice, Coordinator::Write::EventReference
      attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :decision_changed_at, Types::Timestamp
      attribute :assessment_event, Types.Instance(PgEventstore::Event)
    end
  end
end
