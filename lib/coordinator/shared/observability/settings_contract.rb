# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class SettingsContract < Dry::Validation::Contract
      params do
        required(:enabled).filled(:bool)
        required(:mode).filled(:string, included_in?: %w[otlp in_memory])
        required(:environment).filled(:string, max_size?: 100)
        required(:service_name).filled(:string, max_size?: 100)
        required(:service_version).filled(:string, max_size?: 100)
        required(:role).filled(:string, included_in?: Settings::ROLES)
        required(:traces_endpoint).filled(:string, max_size?: 2048)
        required(:metrics_endpoint).filled(:string, max_size?: 2048)
        required(:export_interval_ms).filled(:integer, gteq?: 1000, lteq?: 60000)
        required(:export_timeout_ms).filled(:integer, gteq?: 100, lteq?: 10000)
        required(:trace_sample_ratio).filled(:float, gteq?: 0.0, lteq?: 1.0)
      end

      rule(:traces_endpoint, :metrics_endpoint) do
        %i[traces_endpoint metrics_endpoint].each do |name|
          uri = URI.parse(values.fetch(name))
          unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.fragment
            key(name).failure("must be an HTTP(S) endpoint without userinfo or fragment")
          end
        rescue URI::InvalidURIError
          key(name).failure("must be a valid HTTP(S) endpoint")
        end
      end
    end
  end
end
