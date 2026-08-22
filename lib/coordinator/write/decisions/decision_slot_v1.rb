# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionSlotV1 < Value
      attribute :slot_id, Types::Identifier
      attribute :document, DecisionSlotDocumentV1
      attribute :compound_marker, Coordinator::Shared::CompoundMarker
    end
  end
end
