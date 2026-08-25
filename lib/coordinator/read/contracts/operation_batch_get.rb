# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class OperationBatchGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:batch_id).filled(:string)
        optional(:after_index).maybe(:integer)
        optional(:limit).maybe(:integer)
      end

      rule(:batch_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:after_index) do
        next if value.nil?
        key.failure("must be between 0 and 999") unless (0...Types::OPERATION_BATCH_MAXIMUM_ITEMS).cover?(value)
      end

      rule(:limit) do
        next if value.nil?
        unless (1..Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS).cover?(value)
          key.failure("must be between 1 and #{Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS}")
        end
      end
    end
  end
end
