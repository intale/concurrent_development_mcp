# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CandidateImpactGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:candidate_id).filled(:string)
        required(:direction).filled(:string, included_in?: Types::CANDIDATE_IMPACT_QUERY_DIRECTIONS)
        optional(:after_global_position).maybe(:integer, gteq?: 0)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule(:candidate_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
