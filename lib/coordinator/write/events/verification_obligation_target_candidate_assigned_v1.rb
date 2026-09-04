# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationTargetCandidateAssignedV1 < Base
      contract type: "VerificationObligationTargetCandidateAssigned", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
    end
  end
end
