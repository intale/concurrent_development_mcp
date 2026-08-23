# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligation < ApplicationRecord
    self.primary_key = "obligation_id"
  end
end
