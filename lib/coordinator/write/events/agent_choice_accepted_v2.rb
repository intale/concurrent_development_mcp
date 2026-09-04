# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceAcceptedV2 < Base
      contract type: "AgentChoiceAccepted", version: 2

      attribute :choice_id, Types::Identifier
      attribute :assessment, AgentChoices::ChoiceAssessmentV1
    end
  end
end
