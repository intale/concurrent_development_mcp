# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CoordContexts
      def fetch(change_set_id)
        record = Coordinator::Read::CoordContext.find_by(change_set_id:)
        build_snapshot(record)
      end

      def resolve(scope_kind:, scope_id:)
        scope = Coordinator::Read::CoordContextScope.find_by(scope_kind:, scope_id:)
        return unless scope

        fetch(scope.change_set_id)
      end

      private

      def build_snapshot(record)
        return unless record

        CoordContextSnapshot.new(
          state: Projections::CoordContextStateV1.new(deep_symbolize(record.document)),
          source_positions: record.source_positions.map do |position|
            ProjectionBarrier.new(deep_symbolize(position))
          end,
          last_processed_at: record.last_processed_at.utc.iso8601(6)
        )
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array
          value.map { deep_symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
