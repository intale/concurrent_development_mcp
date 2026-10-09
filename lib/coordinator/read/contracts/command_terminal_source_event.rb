# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CommandTerminalSourceEvent < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: %w[CommandSucceeded CommandRejected])
        required(:schema_version).filled(:integer, included_in?: [ 1, 2 ])
        required(:stream_context).filled(:string, eql?: "CoordinatorControl")
        required(:stream_name).filled(:string, eql?: "Command")
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, eql?: 1)
      end

      rule(:stream_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:event_type, :schema_version) do
        supported = values[:event_type] == "CommandSucceeded" ? values[:schema_version] == 1 : values[:schema_version] == 2
        key(:schema_version).failure("is not supported for the terminal event type") unless supported
      end
    end
  end
end
