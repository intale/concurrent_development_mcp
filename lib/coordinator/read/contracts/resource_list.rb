# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ResourceList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        optional(:kind).maybe(:string, included_in?: %w[file directory])
        optional(:lifecycle_status).maybe(:string, included_in?: %w[registered current inactive])
        optional(:after_resource_id).maybe(:string)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:repository_id) do
        key.failure("must be a valid Repository UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_resource_id) do
        next unless value

        key.failure("must be a valid Resource UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end
    end
  end
end
