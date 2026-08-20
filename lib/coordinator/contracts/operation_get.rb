# frozen_string_literal: true

module Coordinator
  module Contracts
    class OperationGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        optional(:projections).array(:string)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:projections) do
        next unless key?

        unless value.length.between?(1, 10)
          key.failure("must contain between 1 and 10 projection names")
          next
        end

        unknown = value - [ "coord_context_v1" ]
        key.failure("contains an unknown projection") if unknown.any?
        key.failure("must not contain duplicates") unless value.uniq.length == value.length
      end
    end
  end
end
