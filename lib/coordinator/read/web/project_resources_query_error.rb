# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectResourcesQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("Project resources query is invalid")
    end
  end
end
