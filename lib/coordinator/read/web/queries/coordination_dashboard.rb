# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class CoordinationDashboard
    def initialize(
      page_contract: Coordinator::Read::Web::Contracts::CoordinationDashboard::Page.new,
      detail_contract: Coordinator::Read::Web::Contracts::CoordinationDashboard::Detail.new,
      repository: Coordinator::Read::Web::Repositories::CoordinationDashboard.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new
    )
      @page_contract = page_contract
      @detail_contract = detail_contract
      @repository = repository
      @project_reference = project_reference
    end

    def page(input)
      validated = @page_contract.call(input)
      raise_query_error(validated) if validated.failure?

      project_ref = validated[:project_ref]
      @repository.page(
        Coordinator::Read::Web::CoordinationDashboardQueryV1::Page.new(
          project_ref:,
          scope: @project_reference.decode(project_ref),
          kind: validated[:kind],
          first: validated[:first] || 20,
          after_id: validated[:after_id],
          after_sort_value: validated[:after_sort_value],
          presentation_statuses: validated[:presentation_statuses] || [],
          work_item_sort: validated[:work_item_sort] || "updated_at_desc",
          blocking: validated[:blocking],
          domain_status: validated[:domain_status],
          change_set_id: validated[:change_set_id],
          agent_id: validated[:agent_id]
        )
      )
    end

    def detail(input)
      validated = @detail_contract.call(input)
      raise_query_error(validated) if validated.failure?

      project_ref = validated[:project_ref]
      @repository.detail(
        Coordinator::Read::Web::CoordinationDashboardQueryV1::Detail.new(
          project_ref:,
          scope: @project_reference.decode(project_ref),
          kind: validated[:kind],
          id: validated[:id]
        )
      )
    end

    private

    def raise_query_error(result)
      raise Coordinator::Read::Web::CoordinationDashboardQueryError, result.errors.to_h
    end
  end
end
