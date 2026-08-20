# frozen_string_literal: true

module Coordinator
  module Contracts
    class McpSettings < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:allowed_hosts).array(:string)
        required(:allowed_origins).array(:string)
        required(:max_request_bytes).filled(:integer, gteq?: 1, lteq?: 67_108_864)
      end

      rule(:allowed_hosts, :allowed_origins) do
        %i[allowed_hosts allowed_origins].each do |name|
          entries = values[name]
          key(name).failure("must contain at most 100 entries") if entries.length > 100
          key(name).failure("must not contain duplicates") unless entries.uniq.length == entries.length
          key(name).failure("must contain nonblank values") if entries.any? { _1.strip.empty? }
        end
      end
    end
  end
end
