# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactScanStartEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::StartAgentChoiceImpactScan))
        required(:decision_change).value(Types.Instance(AgentChoiceImpacts::DecisionChangeEvidenceV2))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :decision_change, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        decision_change = values[:decision_change]
        lifecycle, link = plan.events
        lifecycle_valid = case lifecycle
                          when Events::AgentChoiceImpactScanStartedV2
                            lifecycle.scan_id == command.scan_id &&
                              lifecycle.decision_change == decision_change &&
                              lifecycle.from_position.zero? &&
                              lifecycle.to_position == decision_change.source_global_position &&
                              lifecycle.page_size == 50
                          when Events::AgentChoiceImpactScanSkippedV2
                            lifecycle.scan_id == command.scan_id
                          else
                            false
                          end
        link_valid = link.is_a?(Events::AgentChoiceImpactScanSourceLinkedV1) &&
          link.scan_id == command.scan_id && link.role == "decision_change" &&
          link.source == decision_change.source_event
        streams_valid = plan.writes.length == 2 && plan.writes.all? { _1.stream == values[:expected_stream] }

        key(:plan).failure("must contain the exact scan decision and decision-change source link") unless
          streams_valid && lifecycle_valid && link_valid
      end
    end
  end
end
