# frozen_string_literal: true

module LiveJobs
  include ActiveJob::TestHelper

  def perform_scheduled_lease_expiry(source_event)
    filter = lambda do |job|
      job.fetch(:job) == Coordinator::Processes::Jobs::ExpireResourceLease &&
        job.fetch(:args).first == source_event.id
    end
    eventually("Lease-expiry job for #{source_event.id} to be scheduled") do
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
      matching = jobs.count(&filter)
      [ matching == 1, matching ]
    end

    performed = perform_enqueued_jobs(only: filter, at: Time.now.utc)
    assert_acceptance_equal(1, performed, "Performed lease-expiry jobs")
  end
end

World(LiveJobs)

Before do
  adapter = ActiveJob::Base.queue_adapter
  adapter.enqueued_jobs.clear if adapter.respond_to?(:enqueued_jobs)
  adapter.performed_jobs.clear if adapter.respond_to?(:performed_jobs)
end
