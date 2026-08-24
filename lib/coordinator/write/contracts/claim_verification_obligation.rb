# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ClaimVerificationObligation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:obligation_id).filled(:string)
        required(:claim_duration_seconds).value(:integer)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:obligation_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:claim_duration_seconds) do
        key.failure("must be between 30 and 3600 seconds") unless (30..3_600).cover?(value)
      end
    end
  end
end
