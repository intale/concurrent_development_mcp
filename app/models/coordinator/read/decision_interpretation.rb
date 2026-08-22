# frozen_string_literal: true

module Coordinator::Read
  class DecisionInterpretation < ApplicationRecord
    self.table_name = "decision_interpretations"
    self.primary_key = "interpretation_id"
  end
end
