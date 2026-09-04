# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepCompletedV2 < Base
      contract type: "CandidateImpactRegistrySweepCompleted", version: 2

      attribute :scan_id, Types::UuidV7
    end
  end
end
