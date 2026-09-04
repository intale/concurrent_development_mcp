# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionBoundaryV1 < Value
    State = Types.Instance(Domain::WorkIntentions::State)
    Observation = Types.Instance(WorkIntentionObservationV1)

    attribute :states, Types::Array.of(State)
    attribute :active_observations, Types::Array.of(Observation)
  end
end
