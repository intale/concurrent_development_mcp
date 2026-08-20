# frozen_string_literal: true

module Coordinator
  module Contracts
    class CommandReceiptSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, eql?: "CommandCompleted")
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string, eql?: "CoordinatorControl")
        required(:stream_name).filled(:string, eql?: "Command")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, eql?: 0)
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
