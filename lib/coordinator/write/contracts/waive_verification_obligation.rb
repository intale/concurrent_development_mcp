# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WaiveVerificationObligation < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "user" ])
          required(:id).filled(:string)
        end
        required(:obligation_id).filled(:string)
        required(:obligation_validity_input_digest).filled(:string)
        required(:reason).hash do
          required(:code).filled(:string, included_in?: Types::VERIFICATION_OBLIGATION_WAIVER_REASON_CODES)
          required(:summary).filled(:string)
        end
      end

      rule(:command_id, :obligation_id) do
        values.values_at(:command_id, :obligation_id).each do |identifier|
          key.failure("must contain valid identifiers") unless Types::IDENTIFIER_PATTERN.match?(identifier)
        end
      end

      rule(:actor) do
        actor_id = value[:id]
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:obligation_validity_input_digest) do
        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:reason) do
        summary = value[:summary]
        unless summary.is_a?(String) && (1..2_000).cover?(summary.length)
          key([ :reason, :summary ]).failure("must contain between 1 and 2000 characters")
        end
      end
    end
  end
end
