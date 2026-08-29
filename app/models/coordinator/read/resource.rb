# frozen_string_literal: true

module Coordinator::Read
  class Resource < ApplicationRecord
    self.primary_key = "resource_id"
  end
end
