# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class Settings < Value
      ROLES = %w[web subscriptions process_managers task_results read_models jobs console].freeze

      attribute :enabled, Types::Bool
      attribute :mode, Types::String.enum("otlp", "in_memory")
      attribute :environment, Types::String
      attribute :service_name, Types::String
      attribute :service_version, Types::String
      attribute :role, Types::String.enum(*ROLES)
      attribute :traces_endpoint, Types::String
      attribute :metrics_endpoint, Types::String
      attribute :export_interval_ms, Types::Integer
      attribute :export_timeout_ms, Types::Integer
      attribute :trace_sample_ratio, Types::Float
    end
  end
end
