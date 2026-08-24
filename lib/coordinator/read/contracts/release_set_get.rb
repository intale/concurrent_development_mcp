# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class ReleaseSetGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:release_set_id).filled(:string)
      end

      rule(:release_set_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
