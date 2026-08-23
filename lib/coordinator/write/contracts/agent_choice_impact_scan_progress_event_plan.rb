# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanProgressEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ProgressAgentChoiceImpactScan))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        write = plan.writes.first
        event = write&.event
        valid_type = event.is_a?(Events::AgentChoiceImpactScanProgressedV1) ||
                     event.is_a?(Events::AgentChoiceImpactScanCompletedV1)
        valid_payload = event&.scan_id == command.scan_id &&
                        event&.previous_checkpoint == command.expected_checkpoint &&
                        event&.previous_from_position == command.previous_from_position &&
                        event&.page_choice_count == command.page_choice_count &&
                        event&.policy_version == command.policy_version

        unless plan.writes.one? && write.stream == values[:expected_stream] && valid_type && valid_payload
          key(:plan).failure("must contain one exact impact scan progress or completion write")
        end
      end
    end
  end
end
