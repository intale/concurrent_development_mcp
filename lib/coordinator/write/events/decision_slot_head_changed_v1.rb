# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionSlotHeadChangedV1 < Base
      contract type: "DecisionSlotHeadChanged", version: 1

      attribute :slot_id, Types::Identifier
      attribute :previous_head, Decisions::DecisionHeadV1.optional
      attribute :head, Decisions::DecisionHeadV1
      attribute :changed_at, Types::Timestamp
    end
  end
end
