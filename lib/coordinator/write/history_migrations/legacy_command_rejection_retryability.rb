# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandRejectionRetryability
      RETRYABLE_CODES = %w[
        concurrency_conflict
        history_migration_changed
        lease_busy
        work_intention_conflict
        resource_boundary_maintenance_required
      ].freeze

      def call(code)
        RETRYABLE_CODES.include?(code)
      end
    end
  end
end
