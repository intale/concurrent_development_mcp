# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpiryJobScheduler
    def call(locator, wait_until:)
      Jobs::ExpireWorkIntention
        .set(wait_until: Time.iso8601(wait_until))
        .perform_later(
          locator.source_event_id,
          locator.resource_stream_id,
          locator.stream_revision
        )
    end
  end
end
