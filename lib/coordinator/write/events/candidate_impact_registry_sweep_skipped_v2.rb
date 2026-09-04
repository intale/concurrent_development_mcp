# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepSkippedV2 < Base
      contract type: "CandidateImpactRegistrySweepSkipped", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :reason, Types::CandidateImpactRegistrySweepSkipReason
    end
  end
end
