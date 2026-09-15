# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class CommandRejectionRetryability
      RETRYABLE_CODES = %i[
        concurrency_conflict
        history_migration_changed
        lease_busy
        work_intention_conflict
        resource_boundary_maintenance_required
      ].freeze

      def call(error)
        RETRYABLE_CODES.include?(error.code)
      end
    end
  end
end
