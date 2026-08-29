# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class PreSemanticOperationBatchCreation < Dry::Validation::Contract
      params do
        required(:event_type).filled(:string, eql?: "OperationBatchCreated")
        required(:stream_id).filled(:string)
        required(:data).hash do
          required(:batch_id).filled(:string)
          required(:items).array(:hash, min_size?: 1) do
            required(:command_input).hash do
              required(:schema).filled(:string, eql?: "command-input/v1")
            end
          end
        end
      end

      rule(:stream_id, :data) do
        key.failure("must match data.batch_id") unless values[:stream_id] == values.dig(:data, :batch_id)
      end
    end
  end
end
