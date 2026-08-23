# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanProgressCommand < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::ProgressAgentChoiceImpactScan))
        required(:expected_identity).filled(:string)
      end

      rule(:command, :expected_identity) do
        unless values[:command].command_id == values[:expected_identity]
          key(:command).failure("command ID must match the canonical checkpoint identity")
        end
      end
    end
  end
end
