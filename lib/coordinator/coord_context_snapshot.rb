# frozen_string_literal: true

module Coordinator
  class CoordContextSnapshot < Value
    attribute :state, Projections::CoordContextStateV1
    attribute :source_positions, Types::Array.of(ProjectionBarrier).constrained(max_size: 256)
    attribute :last_processed_at, Types::Timestamp
  end
end
