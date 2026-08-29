# frozen_string_literal: true

module ResourceScenario
  module_function

  def resolve(event_store:, repository_id:, kind:, path:)
    result = Coordinator::Write::Operations::ExecuteResolveResource.new(event_store:).call(
      command_id: "seed-resource-resolve-#{SecureRandom.uuid_v7}",
      actor: { kind: "agent", id: "test-resource-registrar" },
      repository_id:,
      kind:,
      path:
    )

    result.value!.data.resource_id
  end

  def target(event_store:, repository_id:, kind:, path:, base_blob_oid: nil)
    {
      resource_id: resolve(event_store:, repository_id:, kind:, path:),
      base_blob_oid:
    }
  end

  def resource_events(event_store:, resource_id:)
    event_store.read(
      Coordinator::Write::StreamFactory.new.resource(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def lease_events(event_store:, resource_id:)
    event_store.read_grouped(
      Coordinator::Write::StreamFactory.new.resource_lease(resource_id),
      Coordinator::Write::EventQueries::RESOURCE_LEASE_FOR_RESERVATION
    ).reverse
  end
end
