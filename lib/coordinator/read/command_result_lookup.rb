# frozen_string_literal: true

module Coordinator::Read
  class CommandResultLookup
    def initialize(
      receipts: Repositories::CommandReceipts.new
    )
      @receipts = receipts
    end

    def fetch(request_id)
      @receipts.fetch_by_request_id(request_id)
    end
  end
end
