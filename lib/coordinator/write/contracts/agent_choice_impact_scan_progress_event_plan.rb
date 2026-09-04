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
        event = plan.events.first
        valid = plan.writes.one? && plan.writes.first.stream == values[:expected_stream] &&
          event&.scan_id == command.scan_id
        valid &&= if command.has_more
          event.is_a?(Events::AgentChoiceImpactScanProgressedV2) &&
            event.next_from_position == command.last_processed_position + 1
        else
          event.is_a?(Events::AgentChoiceImpactScanCompletedV2)
        end
        key(:plan).failure("must contain one exact scan progress or completion fact") unless valid
      end
    end
  end
end
