# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ValidityV1 < Value
      attribute :document, ValidityDocumentV1
      attribute :digest, Types::Sha256Digest
    end
  end
end
