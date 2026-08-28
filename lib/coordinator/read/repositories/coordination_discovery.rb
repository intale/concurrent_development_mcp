# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CoordinationDiscovery
      def page(query)
        repository_ids = scoped_repository_ids(query)
        return empty_page(query) if repository_ids.empty?

        relation = matching_contexts(query, repository_ids)
        through = query.cursor&.through_last_processed_at || maximum_last_processed_at(relation)
        return empty_page(query) unless through

        window = relation.where("last_processed_at <= ?", Time.iso8601(through))
        window = after_cursor(window, query.cursor) if query.cursor
        rows = window.order(last_processed_at: :desc, change_set_id: :asc)
          .page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_summary(_1, query.scope, repository_ids) }

        CoordinationPageV1.new(
          scope: query.scope,
          repository_id: query.repository_id,
          statuses: query.statuses,
          items:,
          continuation_cursor: continuation_cursor(through, items, has_more),
          has_more:
        )
      end

      private

      def scoped_repository_ids(query)
        relation = Coordinator::Read::Repository.where(scope: query.scope)
        relation = relation.where(repository_id: query.repository_id) if query.repository_id
        relation.order(:repository_id).pluck(:repository_id)
      end

      def matching_contexts(query, repository_ids)
        Coordinator::Read::CoordContext
          .where("document #>> '{change_set,status}' IN (?)", query.statuses)
          .where(
            <<~SQL.squish,
              EXISTS (
                SELECT 1
                FROM jsonb_array_elements(COALESCE(document -> 'work_items', '[]'::jsonb)) AS work_item
                WHERE work_item ->> 'repository_id' IN (?)
              )
            SQL
            repository_ids
          )
      end

      def maximum_last_processed_at(relation)
        value = relation.maximum(:last_processed_at)
        value&.utc&.iso8601(6)
      end

      def after_cursor(relation, cursor)
        timestamp = Time.iso8601(cursor.after_last_processed_at)
        relation.where(
          "last_processed_at < ? OR (last_processed_at = ? AND change_set_id > ?)",
          timestamp,
          timestamp,
          cursor.after_change_set_id
        )
      end

      def build_summary(record, scope, repository_ids)
        state = Projections::CoordContextStateV1.new(deep_symbolize(record.document))
        scoped_work_items = state.work_items.select { repository_ids.include?(_1.repository_id) }
        scoped_work_item_ids = scoped_work_items.map(&:work_item_id)
        scoped_attempts = state.attempts.select { scoped_work_item_ids.include?(_1.work_item_id) }
        active_attempt_ids = scoped_attempts.reject { %w[abandoned completed].include?(_1.status) }
          .map(&:attempt_id).uniq.sort_by(&:b)
        checkpoint_count = state.candidate_checkpoints.count do |checkpoint|
          scoped_work_item_ids.include?(checkpoint.work_item_id)
        end
        change_set = state.change_set
        raise ProjectionStateError, "Coordination discovery row has no ChangeSet" unless change_set

        CoordinationSummaryV1.new(
          scope:,
          change_set_id: change_set.change_set_id,
          status: change_set.status,
          goal: change_set.goal,
          repository_ids: scoped_work_items.map(&:repository_id).uniq.sort_by(&:b),
          work_item_ids: scoped_work_item_ids.uniq.sort_by(&:b),
          active_attempt_ids:,
          candidate_checkpoint_count: checkpoint_count,
          created_at: change_set.created_at,
          activated_at: change_set.activated_at,
          completed_at: change_set.completed_at,
          last_processed_at: record.last_processed_at.utc.iso8601(6)
        )
      end

      def continuation_cursor(through, items, has_more)
        return unless has_more

        last = items.last
        CoordinationPageV1::Cursor.new(
          through_last_processed_at: through,
          after_last_processed_at: last.last_processed_at,
          after_change_set_id: last.change_set_id
        )
      end

      def empty_page(query)
        CoordinationPageV1.new(
          scope: query.scope,
          repository_id: query.repository_id,
          statuses: query.statuses,
          items: [],
          continuation_cursor: nil,
          has_more: false
        )
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
