# frozen_string_literal: true

module Coordinator::Read
  class DecisionRepositoryMembership < ApplicationRecord
    self.primary_key = nil

    def readonly? = true
  end
end
