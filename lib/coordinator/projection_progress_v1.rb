# frozen_string_literal: true

module Coordinator
  class ProjectionProgressV1 < Value
    attribute :projection_name, Types::String.enum("coord_context_v1")
    attribute :projection_version, Types::Integer.constrained(eql: 1)
    attribute :complete, Types::Strict::Bool
    attribute :missing_barriers, Types::Array.of(ProjectionBarrier).constrained(max_size: 256)
  end
end
