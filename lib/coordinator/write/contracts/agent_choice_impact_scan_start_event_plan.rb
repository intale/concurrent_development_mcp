# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartAgentChoiceImpactScan))
        required(:decision_change).value(Types.Instance(AgentChoiceImpacts::DecisionChangeEvidenceV1))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :decision_change, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        write = plan.writes.first
        event = write&.event
        valid_type = event.is_a?(Events::AgentChoiceImpactScanStartedV1) ||
                     event.is_a?(Events::AgentChoiceImpactScanSkippedV1)
        valid_payload = event&.scan_id == command.scan_id &&
                        event&.decision_change == values[:decision_change] &&
                        event&.policy_version == command.policy_version

        unless plan.writes.one? && write.stream == values[:expected_stream] && valid_type && valid_payload
          key(:plan).failure("must contain one exact impact scan start or skip write")
        end
      end
    end
  end
end
