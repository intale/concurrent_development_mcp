# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationInvalidatedV2 < Base
      contract type: "VerificationObligationInvalidated", version: 2

      attribute :obligation_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end
  end
end
