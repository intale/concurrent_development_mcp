# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectCatalogQueryError < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("project catalog query is invalid")
    end
  end
end
