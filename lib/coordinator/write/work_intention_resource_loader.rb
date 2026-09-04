# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionResourceLoader
    include Dry::Monads[:result]

    def initialize(event_store:, lease_resource_loader: LeaseResourceLoader.new(event_store:))
      @lease_resource_loader = lease_resource_loader
    end

    def call(target, repository_id:)
      result = @lease_resource_loader.call(target, repository_id:)
      return result if result.failure?

      resource = result.value!
      Success(
        WorkIntentionResourceV1.new(
          resource_id: resource.resource_id,
          kind: resource.kind,
          path: resource.path,
          base_blob_oid: resource.base_blob_oid
        )
      )
    end
  end
end
