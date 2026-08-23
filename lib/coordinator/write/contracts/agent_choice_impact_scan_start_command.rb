# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanStartCommand < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::StartAgentChoiceImpactScan))
        required(:decision_change).value(Types.Instance(AgentChoiceImpacts::DecisionChangeEvidenceV1))
        required(:expected_identity).filled(:string)
      end

      rule(:command, :decision_change, :expected_identity) do
        command = values[:command]
        change = values[:decision_change]

        key(:command).failure("source evidence must match the command") unless command.source_event == change.source_event
        unless command.source_global_position == change.source_global_position
          key(:command).failure("source position must match authoritative evidence")
        end
        unless command.scan_id == values[:expected_identity] && command.command_id == values[:expected_identity]
          key(:command).failure("scan and command IDs must match the canonical source identity")
        end
      end
    end
  end
end
