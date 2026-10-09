# frozen_string_literal: true

Rails.application.config.to_prepare do
  Coordinator::Processes::Jobs::ExpireWorkIntention.configure(
    policy: Coordinator::Container["work_intention_expiry_policy"],
    job_scheduler: Coordinator::Container["work_intention_expiry_job_scheduler"]
  )
end
