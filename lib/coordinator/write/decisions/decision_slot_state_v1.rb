# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionSlotStateV1 < Value
      attribute :slot, DecisionSlotV1
      attribute :opened, Types::Bool
      attribute :head, DecisionHeadV1.optional
    end
  end
end
