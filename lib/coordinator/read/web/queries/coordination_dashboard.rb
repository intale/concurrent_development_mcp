# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class CoordinationDashboard
    def initialize(
      contract: Coordinator::Read::Web::Contracts::CoordinationDashboard.new,
      repository: Coordinator::Read::Web::Repositories::CoordinationDashboard.new
    )
      @contract = contract
      @repository = repository
    end

    def call(input)
      validated = @contract.call(input)
      if validated.failure?
        raise Coordinator::Read::Web::CoordinationDashboardQueryError, validated.errors.to_h
      end

      @repository.fetch(
        Coordinator::Read::Web::CoordinationDashboardQueryV1.new(
          repository_id: validated[:repository_id],
          first: validated[:first] || 20,
          change_set_offset: validated[:change_set_offset] || 0,
          work_item_offset: validated[:work_item_offset] || 0,
          dependency_offset: validated[:dependency_offset] || 0,
          presentation_statuses: validated[:presentation_statuses] || [],
          work_item_sort: validated[:work_item_sort] || "work_item_id_asc",
          blocking: validated[:blocking]
        )
      )
    end
  end
end
