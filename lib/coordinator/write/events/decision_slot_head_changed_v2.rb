# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionSlotHeadChangedV2 < Base
      contract type: "DecisionSlotHeadChanged", version: 2

      attribute :slot_id, Types::UuidV7
      attribute :head, Decisions::DecisionHeadV1.optional
    end
  end
end
