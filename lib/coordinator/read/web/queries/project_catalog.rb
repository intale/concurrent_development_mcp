# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class ProjectCatalog
    def initialize(
      discovery_contract: Coordinator::Read::Web::Contracts::ProjectCatalog::Discovery.new,
      overview_contract: Coordinator::Read::Web::Contracts::ProjectCatalog::Overview.new,
      repository: Coordinator::Read::Web::Repositories::ProjectCatalog.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new
    )
      @discovery_contract = discovery_contract
      @overview_contract = overview_contract
      @repository = repository
      @project_reference = project_reference
    end

    def page(input)
      validated = @discovery_contract.call(input)
      raise Coordinator::Read::Web::ProjectCatalogQueryError, validated.errors.to_h if validated.failure?

      @repository.page(
        Coordinator::Read::Web::ProjectCatalogQueriesV1::Discovery.new(
          search: validated[:search],
          sort: validated[:sort] || "scope_asc",
          after_scope: validated[:after_scope],
          first: validated[:first] || 20,
          repositories_first: validated[:repositories_first] || 3
        )
      )
    end

    def overview(input)
      validated = @overview_contract.call(input)
      raise Coordinator::Read::Web::ProjectCatalogQueryError, validated.errors.to_h if validated.failure?

      project_ref = validated[:project_ref]
      @repository.overview(
        Coordinator::Read::Web::ProjectCatalogQueriesV1::Overview.new(
          project_ref:,
          scope: @project_reference.decode(project_ref),
          after_repository_id: validated[:after_repository_id],
          repositories_first: validated[:repositories_first] || 20
        )
      )
    end
  end
end
