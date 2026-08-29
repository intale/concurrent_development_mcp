# frozen_string_literal: true

module Coordinator::Processes
  module Jobs
    class ExpireResourceLease < ApplicationJob
      queue_as :lease_expiry

      def perform(source_event_id, resource_stream_id, stream_revision)
        locator = LeaseExpirySourceLocatorV1.new(
          source_event_id:,
          resource_stream_id:,
          stream_revision:
        )
        result = policy.call(locator)
        if result.failure?
          error = result.failure
          raise LeaseExpiryPolicyRejected, "#{error.code}: #{error.message}"
        end

        decision = result.value!
        return unless decision.is_a?(LeaseExpiryRescheduleV1)

        job_scheduler.call(
          locator,
          wait_until: decision.reschedule_at
        )
      end

      private

      def policy
        Coordinator::Container["lease_expiry_policy"]
      end

      def job_scheduler
        Coordinator::Container["lease_expiry_job_scheduler"]
      end
    end
  end
end
