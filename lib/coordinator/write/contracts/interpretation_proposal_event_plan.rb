# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class InterpretationProposalEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::ProposeDecisionInterpretation))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        events = plan.events

        key(:plan).failure("must contain one proposal and at most one clarification") unless events.length.between?(1, 2)
        key(:plan).failure("must write only to the expected Interpretation stream") unless plan.writes.all? { _1.stream == values[:expected_stream] }
        key(:plan).failure("must begin with DecisionInterpretationProposed") unless events.first.is_a?(Events::DecisionInterpretationProposedV2)
        if events.length == 2 && !events.last.is_a?(Events::DecisionClarificationRequiredV2)
          key(:plan).failure("second event must be DecisionClarificationRequired")
        end
        events.each do |event|
          next if event.interpretation_id == command.interpretation_id && event.source_message_id == command.source_message_id

          key(:plan).failure("event identity must match the command")
        end
      end
    end
  end
end
