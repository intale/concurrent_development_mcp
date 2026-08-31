# frozen_string_literal: true

module Coordinator::Read::Web::Queries
  class ProjectResources
    def initialize(
      contract: Coordinator::Read::Web::Contracts::ProjectResources.new,
      repository: Coordinator::Read::Web::Repositories::ProjectResources.new,
      clock: Coordinator::Shared::SystemClock.new
    )
      @contract = contract
      @repository = repository
      @clock = clock
    end

    def call(input)
      validated = @contract.call(input.merge(lease_as_of: input[:lease_as_of] || @clock.now))
      if validated.failure?
        raise Coordinator::Read::Web::ProjectResourcesQueryError, validated.errors.to_h
      end

      @repository.fetch(
        Coordinator::Read::Web::ProjectResourcesQueryV1.new(
          repository_id: validated[:repository_id],
          first: validated[:first] || 20,
          resource_after_id: validated[:resource_after_id],
          lease_after_id: validated[:lease_after_id],
          lease_as_of: validated[:lease_as_of],
          resource_kind: validated[:resource_kind],
          resource_lifecycle_status: validated[:resource_lifecycle_status]
        )
      )
    end
  end
end
