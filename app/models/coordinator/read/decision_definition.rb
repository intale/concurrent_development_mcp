# frozen_string_literal: true

module Coordinator::Read
  class DecisionDefinition < ApplicationRecord
    self.primary_key = "decision_id"
  end
end
