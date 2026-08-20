# frozen_string_literal: true

module Coordinator
  class CoordContextProgress
    PROJECTION = Projectors::CoordContextV1::PROJECTION

    def initialize(processed_events: Repositories::ProcessedProjectionEvents.new)
      @processed_events = processed_events
    end

    def call(completion)
      missing = @processed_events.missing(
        definition: PROJECTION,
        barriers: completion.projection_barriers.coord_context_v1
      )

      ProjectionProgressV1.new(
        projection_name: "coord_context_v1",
        projection_version: 1,
        complete: missing.empty?,
        missing_barriers: missing
      )
    end
  end
end
