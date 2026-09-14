# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionBoundaryRolloverPolicy
    def initialize(minimum_delta_event_count: EventQueries::WORK_INTENTION_BOUNDARY_ROLLOVER_SOFT_COUNT)
      @minimum_delta_event_count = minimum_delta_event_count
    end

    def call(boundary:, epoch:, through_global_position:)
      return false if epoch.through_global_position && epoch.through_global_position >= through_global_position
      return false if boundary.delta_event_count < @minimum_delta_event_count

      boundary.active_state_count.zero?
    end
  end
end
