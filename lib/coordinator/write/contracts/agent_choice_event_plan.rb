# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::RecordAgentChoice))
        required(:context).value(Types.Instance(DecisionContexts::ContextV1))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :context, :expected_stream) do
        plan = values[:plan]
        command = values[:command]
        recorded, accepted = plan.events
        unless plan.writes.length == 2 && plan.writes.all? { _1.stream == values[:expected_stream] }
          key(:plan).failure("must contain exactly two writes to the target AgentChoice stream")
          next
        end
        unless recorded.is_a?(Events::AgentChoiceRecordedV2) && accepted.is_a?(Events::AgentChoiceAcceptedV2)
          key(:plan).failure("must record and then accept the AgentChoice")
          next
        end
        unless recorded.choice_id == command.choice_id &&
               recorded.choice_type == command.choice_type &&
               recorded.selected == command.selected &&
               recorded.alternatives == command.alternatives &&
               recorded.reason_summary == command.reason_summary &&
               recorded.context == command.context &&
               recorded.decision_context == values[:context]
          key(:plan).failure("recorded choice must preserve the normalized command and authoritative context")
        end
        unless accepted.choice_id == command.choice_id
          key(:plan).failure("acceptance identity must match the recorded choice")
        end
      end
    end
  end
end
