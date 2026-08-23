# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class AgentChoiceImpactList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:attempt_id).filled(:string)
        optional(:after_global_position).maybe(:integer, gteq?: 0)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:attempt_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
