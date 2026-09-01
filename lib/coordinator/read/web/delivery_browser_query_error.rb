# frozen_string_literal: true

module Coordinator::Read::Web
  class DeliveryBrowserQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("delivery browser input is invalid")
    end
  end
end
