# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionSlotOpenedV2 < Base
      contract type: "DecisionSlotOpened", version: 2

      attribute :slot_id, Types::UuidV7
      attribute :slot, Decisions::DecisionSlotDocumentV1
      attribute :opened_by, Types::Identifier
    end
  end
end
