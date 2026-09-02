# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class NaturalKeyV1 < Value
      attribute :document, IdentityDocumentV1
      attribute :digest, Types::Sha256Digest
      attribute :marker, Types::ResourceMarker
    end
  end
end
