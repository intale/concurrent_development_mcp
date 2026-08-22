# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class InterpretationAdjudicationEventPlan < Dry::Validation::Contract
      EVENT_BY_ACTION = {
        "accept" => Events::DecisionInterpretationAcceptedV1,
        "reject" => Events::DecisionInterpretationRejectedV1,
        "request_clarification" => Events::DecisionClarificationRequiredV1
      }.freeze

      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::AdjudicateDecisionInterpretation))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        events = plan.events
        expected_type = EVENT_BY_ACTION.fetch(command.action)

        key(:plan).failure("must contain exactly one lifecycle event") unless events.length == 1
        key(:plan).failure("must write only to the expected Interpretation stream") unless plan.writes.all? { _1.stream == values[:expected_stream] }
        key(:plan).failure("event type must match the command action") unless events.first.is_a?(expected_type)
        unless events.all? { _1.interpretation_id == command.interpretation_id && _1.source_message_id == command.source_message_id }
          key(:plan).failure("event identity must match the command")
        end
        if command.action == "request_clarification" && events.first.origin != "adjudication"
          key(:plan).failure("explicit clarification must record adjudication origin")
        end
      end
    end
  end
end
