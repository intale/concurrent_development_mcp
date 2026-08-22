# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class InterpretationTopicValue < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:expected_schema).filled(:string, included_in?: Types::DECISION_VALUE_SCHEMAS)
        required(:value_schema).filled(:string, included_in?: Types::DECISION_VALUE_SCHEMAS)
      end

      rule(:expected_schema, :value_schema) do
        key(:value_schema).failure("does not match the topic registry") unless values[:expected_schema] == values[:value_schema]
      end
    end
  end
end
