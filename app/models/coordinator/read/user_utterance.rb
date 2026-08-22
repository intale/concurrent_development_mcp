# frozen_string_literal: true

module Coordinator::Read
  class UserUtterance < ApplicationRecord
    self.primary_key = "message_id"
  end
end
