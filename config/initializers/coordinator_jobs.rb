# frozen_string_literal: true

Rails.application.config.after_initialize do
  Coordinator::Container["lease_expiry_job_scheduler"]
end
