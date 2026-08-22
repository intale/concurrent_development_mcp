# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpiryJobScheduler
    def initialize(policy:)
      Jobs::ExpireResourceLease.configure(policy:, job_scheduler: self)
    end

    def call(locator, wait_until:)
      Jobs::ExpireResourceLease
        .set(wait_until: Time.iso8601(wait_until))
        .perform_later(
          locator.source_event_id,
          locator.resource_key_hash,
          locator.stream_revision
        )
    end
  end
end
