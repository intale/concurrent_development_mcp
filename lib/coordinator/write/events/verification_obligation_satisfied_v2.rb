# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationSatisfiedV2 < Base
      contract type: "VerificationObligationSatisfied", version: 2

      attribute :obligation_id, Types::Identifier
    end
  end
end
