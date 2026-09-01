# frozen_string_literal: true

module Coordinator::Read::Web
  class GovernanceBrowserQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("governance browser input is invalid")
    end
  end
end
