# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationEvidenceSelectedV1 < Base
      contract type: "VerificationObligationEvidenceSelected", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :evidence_id, Types::UuidV7
    end
  end
end
