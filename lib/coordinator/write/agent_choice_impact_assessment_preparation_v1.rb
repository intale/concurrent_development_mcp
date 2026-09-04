# frozen_string_literal: true

module Coordinator::Write
  class AgentChoiceImpactAssessmentPreparationV1 < Value
    attribute :assessed_at, Types::Timestamp
      attribute :assessment_event_id, Types::UuidV7
      attribute :accepted_choice_link_event_id, Types::UuidV7
      attribute :decision_change_link_event_id, Types::UuidV7
      attribute :invalidation_event_id, Types::UuidV7
  end
end
