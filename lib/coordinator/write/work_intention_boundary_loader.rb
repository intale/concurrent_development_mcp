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

    def call(
      markers,
      repository_id:,
      at:,
      maximum_count: EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT,
      to_position: EventQueries::RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION,
      resolve_active_observations: true
    )
      epochs = markers.uniq.sort_by(&:b).map { load_epoch(_1, repository_id:) }
      events = epochs.flat_map do |epoch|
        from_position = epoch.through_global_position ? epoch.through_global_position + 1 : 0
        next [] if from_position > to_position

        @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentCoordination",
            stream_name: "ResourceWorkIntention",
            event_types: EventQueries::WORK_INTENTION_LIFECYCLE_EVENT_TYPES,
            markers: [ epoch.marker ],
            maximum_count:,
            direction: :asc,
            from_position:,
            to_position:
          )
        )
      end.uniq(&:id).sort_by { _1.global_position }
      if events.length > maximum_count
        raise EventHistoryLimitExceeded,
              "Work-intention boundary has more than #{maximum_count} delta events"
      end
      states = events.group_by { _1.stream.stream_id }.values.map do |history|
        Domain::WorkIntentions::State.reduce(history.map { deserialize(_1) })
      end

      active_states = states.select { _1.active_at?(at) }
      observations = if resolve_active_observations
                       active_states.map do |state|
                         target = ResourceLeaseTargetV1.new(
                           resource_id: state.resource_id,
                           base_blob_oid: state.base_blob_oid
                         )
                         resource = @resource_loader.call(target, repository_id:)
                         return resource if resource.failure?

                         WorkIntentionObservationV1.new(state:, resource: resource.value!)
                       end
      else
                       []
      end
      Success(
        WorkIntentionBoundaryV1.new(
          epochs:,
          delta_event_count: events.length,
          active_state_count: active_states.length,
          states:,
          active_observations: observations
        )
      )
    end

    private

    def load_epoch(marker, repository_id:)
      event = @event_store.read_latest_marked(
        StreamReference.new(
          context: "DevelopmentCoordination",
          stream_name: "ResourceBoundaryEpoch",
          stream_id: repository_id
        ),
        LatestMarkedEventReadCriteria.new(
          event_type: "ResourceBoundaryEpochRolled",
          marker:
        )
      ).first
      return WorkIntentionBoundaryV1::EpochV1.new(
        marker:,
        epoch: 0,
        through_global_position: nil,
        event: nil
      ) unless event

      payload = deserialize(event)
      unless payload.is_a?(Events::ResourceBoundaryEpochRolledV3) &&
             payload.repository_id == repository_id && payload.boundary_marker == marker
        raise InvalidCommandHistory, "Work-intention boundary epoch is invalid"
      end
      WorkIntentionBoundaryV1::EpochV1.new(
        marker:,
        epoch: payload.epoch,
        through_global_position: payload.through_global_position,
        event:
      )
    end

    def deserialize(event)
      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end
  end
end
