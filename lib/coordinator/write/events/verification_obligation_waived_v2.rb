# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationWaivedV2 < Base
      contract type: "VerificationObligationWaived", version: 2

      attribute :obligation_id, Types::Identifier
      attribute :reason, VerificationObligationWaivers::ReasonV1
    end
  end
end
