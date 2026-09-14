# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionBoundaryV1 < Value
    class EpochV1 < Value
      attribute :marker, Types::ResourceMarker
      attribute :epoch, Types::Integer.constrained(gteq: 0)
      attribute :through_global_position, Types::GlobalPosition.optional
      attribute :event, Types.Instance(PgEventstore::Event).optional
    end

    State = Types.Instance(Domain::WorkIntentions::State)
    Observation = Types.Instance(WorkIntentionObservationV1)

    attribute :epochs, Types::Array.of(Types.Instance(EpochV1)).constrained(min_size: 1, max_size: 1_056)
    attribute :delta_event_count, Types::Integer.constrained(gteq: 0)
    attribute :active_state_count, Types::Integer.constrained(gteq: 0)
    attribute :states, Types::Array.of(State)
    attribute :active_observations, Types::Array.of(Observation)
  end
end
