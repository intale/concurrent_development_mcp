# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanCompletedV2 < Base
      contract type: "CandidateImpactPairScanCompleted", version: 2

      attribute :scan_id, Types::UuidV7
    end
  end
end
