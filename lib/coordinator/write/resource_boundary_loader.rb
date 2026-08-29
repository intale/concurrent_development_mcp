# frozen_string_literal: true

module Coordinator::Write
  class ResourceBoundaryLoader
    class Delta < Value
      Event = Types.Instance(PgEventstore::Event)

      attribute :events, Types::Array.of(Event)
      attribute :truncated, Types::Bool
    end

    class Boundary < Value
      State = Types.Instance(Domain::ResourceLeases::State)

      attribute :marker, Types::Marker
      attribute :epoch, Types::Integer.constrained(gteq: 0)
      attribute :previous_through_global_position, Types::GlobalPosition.optional
      attribute :through_global_position, Types::GlobalPosition.optional
      attribute :delta_count, Types::Integer.constrained(gteq: 0)
      attribute :truncated, Types::Bool
      attribute :states, Types::Array.of(State)
    end

    class Selection < Value
      BoundaryType = Types.Instance(Boundary)
      State = Types.Instance(Domain::ResourceLeases::State)

      attribute :boundaries, Types::Array.of(BoundaryType).constrained(min_size: 1, max_size: 1_056)
      attribute :states, Types::Array.of(State)
    end

    def initialize(event_store:, schema_registry: EventSchemaRegistry.new)
      @event_store = event_store
      @schema_registry = schema_registry
    end

    def call(
      markers,
      maximum_delta_count: EventQueries::RESOURCE_BOUNDARY_DECISION_DELTA_MAXIMUM_COUNT,
      to_position: EventQueries::RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION,
      strict: true
    )
      boundaries = markers.uniq.sort_by(&:b).map do |marker|
        load_boundary(marker, maximum_delta_count:, to_position:, strict:)
      end

      Selection.new(boundaries:, states: merge_states(boundaries))
    end

    def snapshot_stream(marker)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "ResourceBoundaryEpoch",
        stream_id: marker
      )
    end

    private

    def load_boundary(marker, maximum_delta_count:, to_position:, strict:)
      snapshot = load_snapshot(marker)
      previous_position = snapshot&.through_global_position
      delta = load_delta(
        marker,
        from_position: previous_position ? previous_position + 1 : 0,
        to_position:,
        maximum_delta_count:,
        strict:
      )
      states = apply_delta(snapshot, delta.events)
      through_position = delta.events.last ? position!(delta.events.last) : previous_position

      Boundary.new(
        marker:,
        epoch: snapshot&.epoch || 0,
        previous_through_global_position: previous_position,
        through_global_position: through_position,
        delta_count: delta.events.length,
        truncated: delta.truncated,
        states:
      )
    end

    def load_snapshot(marker)
      event = @event_store.read_grouped(
        snapshot_stream(marker),
        EventQueries::RESOURCE_BOUNDARY_LATEST_EPOCH
      ).first
      event && load_event(event)
    end

    def load_delta(marker, from_position:, to_position:, maximum_delta_count:, strict:)
      return Delta.new(events: [], truncated: false) if from_position > to_position

      events = EventQueries.resource_lease_boundary_pages(
        marker,
        from_position:,
        to_position:,
        maximum_count: maximum_delta_count
      ).flat_map { @event_store.read_global_marked_page(_1) }
        .sort_by { position!(_1) }
      truncated = events.length > maximum_delta_count
      if strict && truncated
        raise EventHistoryLimitExceeded,
              "Resource boundary #{marker.inspect} has more than #{maximum_delta_count} delta events"
      end

      Delta.new(events: events.first(maximum_delta_count), truncated:)
    end

    def apply_delta(snapshot, events)
      states = (snapshot&.active_leases || []).to_h do |lease|
        state = lease.to_state
        [ state.identity, state ]
      end
      events.each do |event|
        payload = load_event(event)
        identity = event_identity(payload)
        state = states.fetch(identity, Domain::ResourceLeases::State.initial)
        states[identity] = state.apply(payload)
      end

      states.sort_by { |identity, _state| identity.b }.map(&:last)
    end

    def merge_states(boundaries)
      observations = {}
      boundaries.each do |boundary|
        position = boundary.through_global_position || 0
        boundary.states.each do |state|
          current = observations[state.identity]
          observations[state.identity] = [ position, state ] if current.nil? || position >= current.first
        end
      end

      observations.sort_by { |identity, _observation| identity.b }
        .map { |_identity, observation| observation.last }
    end

    def event_identity(payload)
      return payload.resource_id if payload.respond_to?(:resource_id)

      payload.resource_key_hash
    end

    def load_event(event)
      @schema_registry.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end

    def position!(event)
      event.global_position || raise(EventHistoryLimitExceeded, "Persisted boundary event has no global position")
    end
  end
end
