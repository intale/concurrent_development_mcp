# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class VerificationObligationEvidenceNumberChangedV1 < Coordinator::Write::Events::Base
    contract type: "VerificationObligationEvidenceNumberChanged", version: 1

    attribute :obligation_id, Coordinator::Write::Types::Identifier
    attribute :evidence_number, Coordinator::Write::Types::Integer.constrained(
      gteq: 0, lteq: Coordinator::Write::Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT
    )
  end
end
