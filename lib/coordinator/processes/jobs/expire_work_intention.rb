# frozen_string_literal: true

module Coordinator::Processes
  module Jobs
    class ExpireWorkIntention < ApplicationJob
      queue_as :work_intention_expiry

      class << self
        attr_reader :policy, :job_scheduler

        def configure(policy:, job_scheduler:)
          @policy = policy
          @job_scheduler = job_scheduler
        end
      end

      def perform(source_event_id, resource_stream_id, stream_revision)
        locator = WorkIntentionExpirySourceLocatorV1.new(
          source_event_id:,
          resource_stream_id:,
          stream_revision:
        )
        result = self.class.policy.call(locator)
        if result.failure?
          error = result.failure
          raise WorkIntentionExpiryPolicyRejected, "#{error.code}: #{error.message}"
        end

        decision = result.value!
        return unless decision.is_a?(WorkIntentionExpiryRescheduleV1)

        self.class.job_scheduler.call(
          locator,
          wait_until: decision.reschedule_at
        )
      end
    end
  end
end
