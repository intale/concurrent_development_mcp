# frozen_string_literal: true

module Coordinator::Read
  class CommandCompletionLookup
    def initialize(
      receipts: Repositories::CommandReceipts.new
    )
      @receipts = receipts
    end

    def fetch(command_id)
      @receipts.fetch(command_id)
    end
  end
end
