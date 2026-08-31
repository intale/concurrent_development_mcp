# frozen_string_literal: true

module Coordinator::Read::Web
  class CoordinationDashboardQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("coordination dashboard input is invalid")
    end
  end
end
