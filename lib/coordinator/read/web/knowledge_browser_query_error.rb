# frozen_string_literal: true

module Coordinator::Read::Web
  class KnowledgeBrowserQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("Knowledge browser input is invalid")
    end
  end
end
