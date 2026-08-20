# frozen_string_literal: true

module Coordinator
  class ProjectionBarriers < Value
    attribute :coord_context_v1, Types::Array.of(ProjectionBarrier).constrained(min_size: 1, max_size: 256)
  end
end
