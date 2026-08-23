# frozen_string_literal: true

module Coordinator::Read
  class AgentChoice < ApplicationRecord
    self.primary_key = "choice_id"
  end
end
