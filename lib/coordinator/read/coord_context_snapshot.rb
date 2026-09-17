# frozen_string_literal: true

module Coordinator::Read
  class CoordContextSnapshot < Value
    attribute :state, Projections::CoordContextStateV1
    attribute :source_positions,
              Types::Array.of(ProjectionBarrier).constrained(
                max_size: Projections::CoordContextSourcePositions::MAXIMUM_COUNT
              )
    attribute :last_processed_at, Types::Timestamp
  end
end
