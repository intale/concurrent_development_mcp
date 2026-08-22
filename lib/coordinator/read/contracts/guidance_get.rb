# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class GuidanceGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:message_id).filled(:string)
      end

      rule(:message_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
