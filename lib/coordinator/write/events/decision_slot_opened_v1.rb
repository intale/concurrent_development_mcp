# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionSlotOpenedV1 < Base
      contract type: "DecisionSlotOpened", version: 1

      attribute :slot, Decisions::DecisionSlotV1
      attribute :opened_by, Decisions::DecisionHeadV1
      attribute :opened_at, Types::Timestamp
    end
  end
end
