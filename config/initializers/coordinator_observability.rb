# frozen_string_literal: true

Rails.application.reloader.before_class_unload do
  Coordinator::Shared::Observability::Runtime.shutdown
end

Rails.application.config.to_prepare do
  Coordinator::Shared::Observability::Runtime.configure(environment: Rails.env.to_s)
end

at_exit { Coordinator::Shared::Observability::Runtime.shutdown }
