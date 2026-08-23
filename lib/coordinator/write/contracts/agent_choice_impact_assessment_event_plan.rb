# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactAssessmentEventPlan < Dry::Validation::Contract
      ASSESSMENT_CONTRACT = AgentChoiceImpactAssessment.new

      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::AgentChoiceImpacts::AssessmentState))
        required(:command).value(Types.Instance(Commands::AssessAgentChoiceDecisionImpact))
        required(:assessment_event).value(Types.Instance(EventReference))
        required(:impact_stream).value(Types.Instance(StreamReference))
        required(:choice_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :state, :command, :assessment_event, :impact_stream, :choice_stream) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        assessed = plan.events.first
        unless assessment_write_valid?(plan.writes.first, assessed, state, command, values[:impact_stream])
          key(:plan).failure("first write must record the exact impact assessment")
          next
        end
        assessment_validation = ASSESSMENT_CONTRACT.call(assessment: assessed.assessment)
        if assessment_validation.failure?
          key(:plan).failure("assessment must satisfy its semantic contract")
          next
        end

        if assessed.assessment.outcome == "invalidated"
          invalidation = plan.events.fetch(1, nil)
          unless plan.writes.length == 2 &&
                 invalidation_write_valid?(
                   plan.writes.fetch(1),
                   invalidation,
                   state,
                   command,
                   assessed,
                   values[:assessment_event],
                   values[:choice_stream]
                 )
            key(:plan).failure("invalidating assessment must atomically close the exact Choice")
          end
        elsif plan.writes.length != 1
          key(:plan).failure("non-invalidating assessment must not write a Choice event")
        end
      end

      private

      def assessment_write_valid?(write, event, state, command, expected_stream)
        reconstruction = state.reconstruction
        write&.stream == expected_stream &&
          event.is_a?(Events::AgentChoiceImpactAssessedV1) &&
          event.assessment_id == command.assessment_id &&
          event.choice_id == command.choice_id &&
          event.attempt_id == state.choice.recorded.context.attempt_id &&
          event.accepted_choice == state.choice.accepted_event &&
          event.decision_change == command.decision_change &&
          event.assessment.policy_version == command.policy_version &&
          event.assessment.before_context_digest == reconstruction.before_context.digest &&
          event.assessment.after_context_digest == reconstruction.after_context.digest &&
          event.assessment.before_evaluation == reconstruction.before_evaluation &&
          event.assessment.after_evaluation == reconstruction.after_evaluation &&
          event.assessment.source_advancements == reconstruction.source_advancements
      end

      def invalidation_write_valid?(write, event, state, command, assessed, assessment_event, expected_stream)
        reconstruction = state.reconstruction
        write&.stream == expected_stream &&
          event.is_a?(Events::AgentChoiceInvalidatedByDecisionV1) &&
          event.choice_id == command.choice_id &&
          event.accepted_choice == state.choice.accepted_event &&
          event.assessment_event == assessment_event &&
          event.decision_change_event == command.decision_change.source_event &&
          event.previous_context_digest == reconstruction.before_context.digest &&
          event.resulting_context_digest == reconstruction.after_context.digest &&
          event.reason == assessed.assessment.reason
      end
    end
  end
end
