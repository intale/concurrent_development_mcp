# frozen_string_literal: true

Rails.application.config.to_prepare do
  Coordinator::Processes::Jobs::ExpireResourceLease.configure(
    policy: Coordinator::Container["lease_expiry_policy"],
    job_scheduler: Coordinator::Container["lease_expiry_job_scheduler"]
  )
end
