# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationSourceCandidateAssignedV1 < Base
      contract type: "VerificationObligationSourceCandidateAssigned", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
    end
  end
end
