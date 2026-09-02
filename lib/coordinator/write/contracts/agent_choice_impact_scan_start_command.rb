# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanStartCommand < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::StartAgentChoiceImpactScan))
        required(:decision_change).value(Types.Instance(AgentChoiceImpacts::DecisionChangeEvidenceV1))
      end

      rule(:command, :decision_change) do
        command = values[:command]
        change = values[:decision_change]

        key(:command).failure("source evidence must match the command") unless command.source_event == change.source_event
        unless command.source_global_position == change.source_global_position
          key(:command).failure("source position must match authoritative evidence")
        end
        key(:command).failure("scan ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.scan_id)
        key(:command).failure("command ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.command_id)
      end
    end
  end
end
