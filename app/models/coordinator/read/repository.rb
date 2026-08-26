# frozen_string_literal: true

module Coordinator::Read
  class Repository < ApplicationRecord
    self.primary_key = "repository_id"
  end
end
