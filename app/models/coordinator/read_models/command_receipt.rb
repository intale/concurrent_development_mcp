# frozen_string_literal: true

module Coordinator
  module ReadModels
    class CommandReceipt < ApplicationRecord
      self.primary_key = "command_id"
    end
  end
end
