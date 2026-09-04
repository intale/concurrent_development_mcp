# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactAssessmentRecordedV1 < Base
      contract type: "AgentChoiceImpactAssessmentRecorded", version: 1

      attribute :assessment_id, Types::UuidV7
      attribute :choice_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :assessment, AgentChoiceImpacts::ImpactAssessmentV2
    end
  end
end
