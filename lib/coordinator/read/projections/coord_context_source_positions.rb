# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextSourcePositions
      MAXIMUM_COUNT = 1 +
        CoordContextStateV1::WORK_ITEM_LIMIT +
        CoordContextStateV1::RECENT_ATTEMPT_LIMIT +
        CoordContextStateV1::CANDIDATE_CHECKPOINT_LIMIT +
        (CoordContextStateV1::RECENT_ATTEMPT_LIMIT * CoordContextStateV1::WORK_INTENTION_LIMIT)

      def call(positions:, state:)
        retained = retained_streams(state)
        positions.filter_map do |position|
          barrier = position.is_a?(ProjectionBarrier) ? position : ProjectionBarrier.new(deep_symbolize(position))
          barrier if retained.include?(stream_key(barrier))
        end.sort_by { stream_key(_1) }.freeze
      end

      private

      def retained_streams(state)
        streams = []
        if state.change_set
          streams << [ "DevelopmentPlanning", "ChangeSet", state.change_set.change_set_id ]
        end
        state.work_items.each do |work_item|
          streams << [ "DevelopmentExecution", "WorkItem", work_item.work_item_id ]
        end
        state.attempts.each do |attempt|
          streams << [ "DevelopmentExecution", "Attempt", attempt.attempt_id ]
          attempt.work_intention_set&.intentions&.each do |intention|
            streams << [ "DevelopmentCoordination", "ResourceWorkIntention", intention.intention_id ]
          end
        end
        state.candidate_checkpoints.each do |checkpoint|
          streams << [ "DevelopmentIntegration", "Candidate", checkpoint.candidate_id ]
        end
        streams.to_set.freeze
      end

      def stream_key(barrier)
        [ barrier.stream_context, barrier.stream_name, barrier.stream_id ]
      end

      def deep_symbolize(value)
        value.to_h { |key, nested| [ key.to_sym, nested ] }
      end
    end
  end
end
