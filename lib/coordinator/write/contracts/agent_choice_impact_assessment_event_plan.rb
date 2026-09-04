# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactAssessmentEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::AgentChoiceImpacts::AssessmentState))
        required(:command).value(Types.Instance(Commands::AssessAgentChoiceDecisionImpact))
        required(:impact_stream).value(Types.Instance(StreamReference))
        required(:choice_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :state, :command, :impact_stream, :choice_stream) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        assessed, accepted_link, change_link, invalidation = plan.events

        unless plan.writes.first(3).all? { _1.stream == values[:impact_stream] } &&
               assessed.is_a?(Events::AgentChoiceImpactAssessmentRecordedV1) &&
               accepted_link.is_a?(Events::AgentChoiceImpactSourceLinkedV1) &&
               change_link.is_a?(Events::AgentChoiceImpactSourceLinkedV1)
          key(:plan).failure("must begin with one assessment and its two source links")
          next
        end
        unless assessed.assessment_id == command.assessment_id &&
               assessed.choice_id == command.choice_id &&
               assessed.attempt_id == state.choice.recorded.context.attempt_id &&
               assessed.assessment.before_evaluation == state.reconstruction.before_evaluation &&
               assessed.assessment.after_evaluation == state.reconstruction.after_evaluation &&
               accepted_link.assessment_id == command.assessment_id &&
               accepted_link.role == "accepted_choice" &&
               accepted_link.source == state.choice.accepted_event &&
               change_link.assessment_id == command.assessment_id &&
               change_link.role == "decision_change" &&
               change_link.source == command.decision_change.source_event
          key(:plan).failure("assessment facts must retain the exact decision evidence")
        end

        if assessed.assessment.outcome == "invalidated"
          unless plan.writes.length == 4 &&
                 plan.writes.last.stream == values[:choice_stream] &&
                 invalidation.is_a?(Events::AgentChoiceInvalidatedByDecisionV2) &&
                 invalidation.choice_id == command.choice_id &&
                 invalidation.reason == assessed.assessment.reason
            key(:plan).failure("invalidating assessment must atomically close the exact Choice")
          end
        elsif plan.writes.length != 3
          key(:plan).failure("non-invalidating assessment must not write a Choice event")
        end
      end
    end
  end
end
