# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanCompletedV2 < Base
      contract type: "AgentChoiceImpactScanCompleted", version: 2

      attribute :scan_id, Types::UuidV7
    end
  end
end
