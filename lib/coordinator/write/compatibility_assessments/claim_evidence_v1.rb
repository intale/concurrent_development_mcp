# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class ClaimEvidenceV1 < Value
      attribute :claim_id, Types::UuidV7
      attribute :claimant_id, Types::Identifier
      attribute :fencing_token, Types::FencingToken
      attribute :claim_event, EventReference
    end
  end
end
