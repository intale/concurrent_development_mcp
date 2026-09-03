# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class CommandRejectionRetryability
      RETRYABLE_CODES = %i[
        concurrency_conflict
        lease_busy
        resource_boundary_maintenance_required
      ].freeze

      def call(error)
        RETRYABLE_CODES.include?(error.code)
      end
    end
  end
end
