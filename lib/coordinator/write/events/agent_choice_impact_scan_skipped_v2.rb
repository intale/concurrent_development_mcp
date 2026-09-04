# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AgentChoiceImpactScanSkippedV2 < Base
      contract type: "AgentChoiceImpactScanSkipped", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :reason, Types::AgentChoiceImpactScanSkipReason
    end
  end
end
