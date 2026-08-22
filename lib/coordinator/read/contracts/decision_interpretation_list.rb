# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionInterpretationList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:message_id).filled(:string)
        optional(:after_revision).maybe(:integer, gteq?: -1)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:message_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
