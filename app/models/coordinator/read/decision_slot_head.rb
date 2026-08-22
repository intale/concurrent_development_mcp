# frozen_string_literal: true

module Coordinator::Read
  class DecisionSlotHead < ApplicationRecord
    self.primary_key = "slot_id"
  end
end
