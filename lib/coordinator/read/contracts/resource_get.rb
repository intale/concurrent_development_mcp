# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ResourceGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:resource_id).filled(:string)
      end

      rule(:resource_id) do
        key.failure("must be a valid Resource UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end
    end
  end
end
