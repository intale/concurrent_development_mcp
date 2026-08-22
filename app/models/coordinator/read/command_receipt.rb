# frozen_string_literal: true

module Coordinator::Read
  class CommandReceipt < ApplicationRecord
    self.primary_key = "command_id"
  end
end
