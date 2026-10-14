# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CoordContexts
      def initialize(
        state_loader: Projections::CoordContextStateLoader.new,
        source_positions: Projections::CoordContextSourcePositions.new
      )
        @state_loader = state_loader
        @source_positions = source_positions
      end

      def fetch(change_set_id)
        record = Coordinator::Read::CoordContext.find_by(change_set_id:)
        build_snapshot(record)
      end

      def resolve(scope_kind:, scope_id:)
        scope = Coordinator::Read::CoordContextScope.find_by(scope_kind:, scope_id:)
        return unless scope

        fetch(scope.change_set_id)
      end

      def attempt_page(work_item_id:, after_authorized_global_position:, limit:)
        relation = Coordinator::Read::AttemptHistory.where(work_item_id:)
        if after_authorized_global_position
          relation = relation.where("authorized_global_position > ?", after_authorized_global_position)
        end
        records = relation.order(:authorized_global_position, :attempt_id).limit(limit + 1).to_a
        has_more = records.length > limit
        items = records.first(limit).map { build_attempt_history(_1) }

        QueryResultV1::AttemptHistoryPage.new(
          work_item_id:,
          items:,
          next_authorized_global_position: has_more ? items.last.authorized_global_position : nil,
          has_more:
        )
      end

      private

      def build_attempt_history(record)
        QueryResultV1::AttemptHistoryView.new(
          attempt_id: record.attempt_id,
          change_set_id: record.change_set_id,
          work_item_id: record.work_item_id,
          agent_id: record.agent_id,
          base_snapshots: record.base_snapshots.map do
            Coordinator::Write::RepositorySnapshotV1.new(deep_symbolize(_1))
          end,
          status: record.status,
          authorization_event: Coordinator::Write::EventReference.new(deep_symbolize(record.authorization_event)),
          authorized_global_position: record.authorized_global_position,
          authorized_at: record.authorized_at_domain.utc.iso8601(6),
          started_at: record.started_at_domain&.utc&.iso8601(6),
          selected_candidate_id: record.selected_candidate_id,
          selected_candidate_event: record.selected_candidate_event &&
            Coordinator::Write::EventReference.new(deep_symbolize(record.selected_candidate_event)),
          abandonment_reason: record.abandonment_reason,
          terminal_event: record.terminal_event &&
            Coordinator::Write::EventReference.new(deep_symbolize(record.terminal_event)),
          terminal_at: record.terminal_at_domain&.utc&.iso8601(6)
        )
      end

      def build_snapshot(record)
        return unless record

        state = @state_loader.call(record.document)
        CoordContextSnapshot.new(
          state:,
          source_positions: @source_positions.call(positions: record.source_positions, state:),
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
