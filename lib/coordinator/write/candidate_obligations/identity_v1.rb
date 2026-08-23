# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class IdentityV1 < Value
      attribute :document, IdentityDocumentV1
      attribute :digest, Types::Sha256Digest
      attribute :obligation_id, Types::Identifier
    end
  end
end
