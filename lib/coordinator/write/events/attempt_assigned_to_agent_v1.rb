# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptAssignedToAgentV1 < Base
      contract type: "AttemptAssignedToAgent", version: 1

      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
    end
  end
end
