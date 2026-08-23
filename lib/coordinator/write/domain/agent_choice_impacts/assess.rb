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

        def call(state:, command:, assessed_at:, assessment_event:)
          outcome, reason = outcome(state)
          assessment = build_assessment(state.reconstruction, command, outcome, reason)
          writes = [ assessment_write(state, command, assessment, assessed_at) ]
          if outcome == "invalidated"
            writes << invalidation_write(state, command, assessment_event, reason, assessed_at)
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
          Coordinator::Write::AgentChoiceImpacts::AssessmentV1.new(
            policy_version: command.policy_version,
            before_context_digest: reconstruction.before_context.digest,
            after_context_digest: reconstruction.after_context.digest,
            before_evaluation: reconstruction.before_evaluation,
            after_evaluation: reconstruction.after_evaluation,
            source_advancements: reconstruction.source_advancements,
            outcome:,
            reason:
          )
        end

        def assessment_write(state, command, assessment, assessed_at)
          EventWrite.new(
            stream: @stream_factory.agent_choice_impact(command.assessment_id),
            event: Events::AgentChoiceImpactAssessedV1.new(
              assessment_id: command.assessment_id,
              choice_id: command.choice_id,
              attempt_id: state.choice.recorded.context.attempt_id,
              accepted_choice: state.choice.accepted_event,
              decision_change: command.decision_change,
              assessment:,
              assessed_at:
            )
          )
        end

        def invalidation_write(state, command, assessment_event, reason, assessed_at)
          EventWrite.new(
            stream: @stream_factory.agent_choice(command.choice_id),
            event: Events::AgentChoiceInvalidatedByDecisionV1.new(
              choice_id: command.choice_id,
              accepted_choice: state.choice.accepted_event,
              assessment_event:,
              decision_change_event: command.decision_change.source_event,
              previous_context_digest: state.reconstruction.before_context.digest,
              resulting_context_digest: state.reconstruction.after_context.digest,
              reason:,
              invalidated_at: assessed_at
            )
          )
        end
      end
    end
  end
end
