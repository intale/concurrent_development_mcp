# frozen_string_literal: true

Rails.application.reloader.before_class_unload do
  Coordinator::Shared::Observability::Runtime.shutdown
end

Rails.application.config.to_prepare do
  Coordinator::Shared::Observability::Runtime.configure(environment: Rails.env.to_s)
end

coordinator_boot_pid = Process.pid
ActiveSupport.on_load(:solid_queue) do
  %i[worker dispatcher scheduler].each do |process|
    SolidQueue.public_send(:"on_#{process}_start") do
      Coordinator::Shared::Observability::Runtime.ensure_process
    end
    SolidQueue.public_send(:"on_#{process}_stop") do
      Coordinator::Shared::Observability::Runtime.shutdown if Process.pid != coordinator_boot_pid
    end
  end
end

at_exit { Coordinator::Shared::Observability::Runtime.shutdown }
