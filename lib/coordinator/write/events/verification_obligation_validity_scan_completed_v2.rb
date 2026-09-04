# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanCompletedV2 < Base
      contract type: "VerificationObligationValidityScanCompleted", version: 2

      attribute :scan_id, Types::UuidV7
    end
  end
end
