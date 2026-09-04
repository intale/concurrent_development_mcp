# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanSkippedV2 < Base
      contract type: "CandidateImpactPairScanSkipped", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :reason, Types::CandidateImpactPairScanSkipReason
    end
  end
end
