# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoiceImpacts
      class Assess
        include Dry::Monads[:result]

        INVALIDATION_REASONS = {
          "blocked" => "blocking_policy_introduced",
          "confirmation_required" => "confirmation_policy_introduced",
          "conflict" => "decision_conflict_introduced",
          "unsupported" => "unsupported_policy_introduced",
          "unresolved" => "unresolved_policy_introduced"
        }.freeze

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          outcome, reason = outcome(state)
          assessment = build_assessment(state.reconstruction, command, outcome, reason)
          writes = [
            assessment_write(state, command, assessment),
            source_link_write(command, "accepted_choice", state.choice.accepted_event),
            source_link_write(command, "decision_change", command.decision_change.source_event)
          ]
          if outcome == "invalidated"
            writes << invalidation_write(command, reason)
          end

          Success(EventPlan.new(writes:))
        end

        private

        def outcome(state)
          return [ "already_invalidated", "choice_terminal" ] if state.choice.invalidation
          return [ "not_applicable", "attempt_not_active" ] unless state.attempt.status == "active"
          if state.reconstruction.source_already_observed
            return [ "not_applicable", "change_already_observed" ]
          end
          unless state.reconstruction.before_evaluation.status == "allowed"
            return [ "still_valid", "noncompliance_preceded_change" ]
          end
          if state.reconstruction.after_evaluation.status == "allowed"
            return [ "still_valid", "compliant_or_advisory" ]
          end

          [ "invalidated", INVALIDATION_REASONS.fetch(state.reconstruction.after_evaluation.status) ]
        end

        def build_assessment(reconstruction, command, outcome, reason)
          Coordinator::Write::AgentChoiceImpacts::ImpactAssessmentV2.new(
            before_evaluation: reconstruction.before_evaluation,
            after_evaluation: reconstruction.after_evaluation,
            outcome:,
            reason:
          )
        end

        def assessment_write(state, command, assessment)
          EventWrite.new(
            stream: @stream_factory.agent_choice_impact(command.assessment_id),
            event: Events::AgentChoiceImpactAssessmentRecordedV1.new(
              assessment_id: command.assessment_id,
              choice_id: command.choice_id,
              attempt_id: state.choice.recorded.context.attempt_id,
              assessment:
            )
          )
        end

        def source_link_write(command, role, source)
          EventWrite.new(
            stream: @stream_factory.agent_choice_impact(command.assessment_id),
            event: Events::AgentChoiceImpactSourceLinkedV1.new(
              assessment_id: command.assessment_id,
              role:,
              source:
            )
          )
        end

        def invalidation_write(command, reason)
          EventWrite.new(
            stream: @stream_factory.agent_choice(command.choice_id),
            event: Events::AgentChoiceInvalidatedByDecisionV2.new(
              choice_id: command.choice_id,
              reason:
            )
          )
        end
      end
    end
  end
end
