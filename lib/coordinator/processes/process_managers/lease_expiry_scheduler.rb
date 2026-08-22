# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class LeaseExpiryScheduler
      def initialize(
        source_builder: LeaseExpirySourceBuilder.new,
        job_scheduler:
      )
        @source_builder = source_builder
        @job_scheduler = job_scheduler
      end

      def call(event)
        source = @source_builder.call(event)
        locator = LeaseExpirySourceLocatorV1.from_source(source)
        @job_scheduler.call(locator, wait_until: source.payload.expires_at)
        nil
      end
    end
  end
end
