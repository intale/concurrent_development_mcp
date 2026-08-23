# frozen_string_literal: true

module Coordinator::Read
  class Candidate < ApplicationRecord
    self.primary_key = "candidate_id"
  end
end
