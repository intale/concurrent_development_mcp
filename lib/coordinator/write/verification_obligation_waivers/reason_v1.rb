# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationWaivers
    class ReasonV1 < Value
      attribute :code, Types::VerificationObligationWaiverReasonCode
      attribute :summary, Types::VerificationObligationWaiverReasonSummary
    end
  end
end
