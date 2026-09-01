# frozen_string_literal: true

module Coordinator::Read::Web
  class GovernanceBrowserReadError < StandardError
    attr_reader :details

    def initialize(command_id:, reason:)
      @details = {
        entity: "command_receipt",
        command_id:,
        reason:
      }.freeze
      super("Projected command receipt is invalid")
    end
  end
end
