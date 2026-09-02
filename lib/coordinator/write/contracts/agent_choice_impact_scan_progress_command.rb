# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanProgressCommand < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::ProgressAgentChoiceImpactScan))
      end

      rule(:command) do
        key.failure("command ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(value.command_id)
      end
    end
  end
end
