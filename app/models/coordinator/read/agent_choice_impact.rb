# frozen_string_literal: true

module Coordinator::Read
  class AgentChoiceImpact < ApplicationRecord
    self.primary_key = "assessment_id"
  end
end
