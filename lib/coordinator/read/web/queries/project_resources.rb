# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class ProjectResources
    def initialize(
      collection_contract: Coordinator::Read::Web::Contracts::ProjectResources::Collection.new,
      detail_contract: Coordinator::Read::Web::Contracts::ProjectResources::Detail.new,
      repository: Coordinator::Read::Web::Repositories::ProjectResources.new,
      resource_get: Coordinator::Read::Queries::ResourceGet.new,
      project_reference: Coordinator::Read::Web::ProjectReference.new,
      clock: Coordinator::Shared::SystemClock.new
    )
      @collection_contract = collection_contract
      @detail_contract = detail_contract
      @repository = repository
      @resource_get = resource_get
      @project_reference = project_reference
      @clock = clock
    end

    def resources(input)
      @repository.resources(collection_query(input.merge(kind: "resources")))
    end

    def resource(input)
      query = detail_query(input.merge(kind: "resource"))
      result = @resource_get.call(resource_id: query.id).value!
      return unless result.status == "ok"

      @repository.resource(query, result.data.resource)
    end

    def active_work_intentions(input)
      @repository.active_work_intentions(collection_query(input.merge(kind: "active_work_intentions")))
    end

    def work_intention(input)
      @repository.work_intention(detail_query(input.merge(kind: "work_intention")))
    end

    private

    def collection_query(input)
      validated = @collection_contract.call(input.merge(as_of: input[:as_of] || @clock.now))
      raise_query_error(validated) if validated.failure?

      values = validated.to_h
      project_ref = values.fetch(:project_ref)
      Coordinator::Read::Web::ProjectResourcesQueryV1::Collection.new(
        **values,
        scope: @project_reference.decode(project_ref),
        first: values[:first] || 20,
        after_id: values[:after_id],
        after_updated_at: values[:after_updated_at],
        sort: values[:sort] || "newest_first",
        path: values[:path],
        resource_kind: values[:resource_kind],
        resource_lifecycle_status: values[:resource_lifecycle_status],
        agent_id: values[:agent_id],
        change_set_id: values[:change_set_id],
        work_item_id: values[:work_item_id],
        attempt_id: values[:attempt_id],
        mode: values[:mode]
      )
    end

    def detail_query(input)
      validated = @detail_contract.call(input.merge(as_of: input[:as_of] || @clock.now))
      raise_query_error(validated) if validated.failure?

      values = validated.to_h
      project_ref = values.fetch(:project_ref)
      Coordinator::Read::Web::ProjectResourcesQueryV1::Detail.new(
        **values,
        scope: @project_reference.decode(project_ref)
      )
    end

    def raise_query_error(result)
      raise Coordinator::Read::Web::ProjectResourcesQueryError, result.errors.to_h
    end
  end
end
