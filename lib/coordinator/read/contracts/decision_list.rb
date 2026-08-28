# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DecisionList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        optional(:topic_id).maybe(:string)
        optional(:policy_status).maybe(:string)
        optional(:after_decision_id).maybe(:string)
        optional(:limit).maybe(:integer)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7 Repository ID") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:topic_id) do
        next if value.nil? || Types::IDENTIFIER_PATTERN.match?(value)

        key.failure("must be a valid topic identifier")
      end

      rule(:policy_status) do
        next if value.nil? || Types::DECISION_POLICY_STATUSES.include?(value)

        key.failure("must be a Decision policy status")
      end

      rule(:after_decision_id) do
        next if value.nil? || Types::IDENTIFIER_PATTERN.match?(value)

        key.failure("must be a valid Decision ID")
      end

      rule(:limit) do
        next if value.nil? || (1..Types::DECISION_DISCOVERY_MAXIMUM_ITEMS).cover?(value)

        key.failure("must be between 1 and #{Types::DECISION_DISCOVERY_MAXIMUM_ITEMS}")
      end
    end
  end
end
