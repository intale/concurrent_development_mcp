# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionBoundaryLoader
    include Dry::Monads[:result]

    def initialize(
      event_store:,
      schema_registry: EventSchemaRegistry.new,
      resource_loader: WorkIntentionResourceLoader.new(event_store:)
    )
      @event_store = event_store
      @schema_registry = schema_registry
      @resource_loader = resource_loader
    end

    def call(markers, repository_id:, at:)
      events = @event_store.read_global_marked(EventQueries.work_intention_boundary(markers))
      states = events.group_by { _1.stream.stream_id }.values.map do |history|
        Domain::WorkIntentions::State.reduce(history.map { deserialize(_1) })
      end

      observations = states.filter_map do |state|
        next unless state.active_at?(at)

        target = ResourceLeaseTargetV1.new(
          resource_id: state.resource_id,
          base_blob_oid: state.base_blob_oid
        )
        resource = @resource_loader.call(target, repository_id:)
        return resource if resource.failure?

        WorkIntentionObservationV1.new(state:, resource: resource.value!)
      end
      Success(WorkIntentionBoundaryV1.new(states:, active_observations: observations))
    end

    private

    def deserialize(event)
      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end
  end
end
