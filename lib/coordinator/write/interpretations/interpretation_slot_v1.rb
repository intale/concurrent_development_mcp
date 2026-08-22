# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationSlotV1 < Value
      attribute :document, InterpretationSlotDocumentV1
      attribute :scope_digest, Types::Sha256Digest
      attribute :compound_marker, Coordinator::Shared::CompoundMarker
    end
  end
end
