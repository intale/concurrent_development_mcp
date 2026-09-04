# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoices
      class Record
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new, policy_evaluator: PolicyEvaluator.new)
          @stream_factory = stream_factory
          @policy_evaluator = policy_evaluator
        end

        def call(state:, command:)
          denial = denied(state, command)
          return denial if denial

          evaluation = @policy_evaluator.call(
            resolution: state.resolution,
            selected_option_id: command.selected.option_id
          )
          assessment = assess(evaluation, state.resolution.effective_decision, command)
          return assessment if assessment.failure?

          Success(build_plan(command, state.current_context, assessment.value!))
        end

        private

        def denied(state, command)
          return choice_exists(state.existing_choice, command) if state.existing_choice

          attempt_denial = denied_attempt(state.attempt, command)
          return attempt_denial if attempt_denial

          resolution = state.resolution
          unless resolution.unsupported_dimensions.empty?
            return failure(
              :unsupported_decision_context,
              "Authoritative Decisions require unsupported context dimensions",
              dimensions: resolution.unsupported_dimensions,
              decision_heads: resolution.unsupported_decisions.map(&:to_h)
            )
          end
          unless resolution.unresolved_decisions.empty?
            return failure(
              :decision_partition_state_invalid,
              "DecisionPartition references Decision heads that cannot be reconstructed",
              decision_heads: resolution.unresolved_decisions.map(&:to_h)
            )
          end

          submitted = command.decision_context
          current = state.current_context
          changed_partitions = changed_partition_ids(submitted.document.partitions, current.document.partitions)
          unless changed_partitions.empty?
            return failure(
              :stale_decision_context,
              "Submitted Decision context no longer matches authoritative partitions",
              changed_partition_ids: changed_partitions,
              submitted_digest: submitted.digest,
              current_digest: current.digest,
              topic_id: command.choice_type,
              context: command.context.to_h
            )
          end
          unless submitted.document.to_h == current.document.to_h && submitted.digest == current.digest
            return failure(
              :decision_context_mismatch,
              "Submitted Decision context does not match its authoritative reconstruction",
              submitted_digest: submitted.digest,
              current_digest: current.digest
            )
          end
          return unless resolution.conflict

          failure(
            :decision_context_conflict,
            "Authoritative Decision context has tied most-specific Decisions",
            conflict: resolution.conflict.to_h
          )
        end

        def denied_attempt(attempt, command)
          return attempt_failure(:attempt_not_found, "Attempt does not exist", command) if attempt.absent?
          return attempt_failure(:attempt_not_active, "Attempt is not active", command) unless attempt.status == "active"

          unless attempt.change_set_id == command.context.change_set_id &&
                 attempt.work_item_id == command.context.work_item_id &&
                 attempt.attempt_id == command.context.attempt_id
            return attempt_failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          unless attempt.agent_id == command.actor.id
            return attempt_failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
          end

          snapshot = attempt.base_snapshots.find do |candidate|
            candidate.repository_id == command.context.repository_id
          end
          return if snapshot

          attempt_failure(:repository_base_mismatch, "Repository does not belong to the Attempt", command)
        end

        def changed_partition_ids(submitted, current)
          submitted_by_id = submitted.to_h { [ _1.partition.partition_id, _1.to_h ] }
          current_by_id = current.to_h { [ _1.partition.partition_id, _1.to_h ] }
          (submitted_by_id.keys | current_by_id.keys)
            .select { submitted_by_id[_1] != current_by_id[_1] }
            .sort_by(&:b)
        end

        def assess(evaluation, decision, command)
          case evaluation.status
          when "allowed"
            Success(accepted_assessment(evaluation))
          when "blocked"
            policy_failure(:agent_choice_blocked_by_decision, "Agent choice is blocked by an active Decision", decision, command)
          when "confirmation_required"
            policy_failure(:agent_choice_confirmation_required, "Agent choice requires confirmation", decision, command)
          when "unsupported"
            unsupported_value(decision)
          end
        end

        def accepted_assessment(evaluation)
          Coordinator::Write::AgentChoices::ChoiceAssessmentV1.new(
            basis: evaluation.basis,
            based_on_decisions: [ evaluation.effective_decision ].compact,
            warnings: evaluation.warnings
          )
        end

        def unsupported_value(decision)
          failure(
            :unsupported_decision_context,
            "Effective Decision does not use the testing.framework named-choice value",
            dimensions: [ "value.schema" ],
            decision_heads: [ decision.head.to_h ]
          )
        end

        def policy_failure(code, message, decision, command)
          failure(
            code,
            message,
            decision_head: decision.head.to_h,
            effect: decision.effect,
            selected_option_id: command.selected.option_id,
            decision_option_id: decision.value.name,
            on_violation: decision.enforcement.on_violation
          )
        end

        def build_plan(command, context, assessment)
          stream = @stream_factory.agent_choice(command.choice_id)
          EventPlan.new(
            writes: [
              EventWrite.new(
                stream:,
                event: Events::AgentChoiceRecordedV2.new(
                  choice_id: command.choice_id,
                  choice_type: command.choice_type,
                  selected: command.selected,
                  alternatives: command.alternatives,
                  reason_summary: command.reason_summary,
                  context: command.context,
                  decision_context: context
                )
              ),
              EventWrite.new(
                stream:,
                event: Events::AgentChoiceAcceptedV2.new(
                  choice_id: command.choice_id,
                  assessment:
                )
              )
            ]
          )
        end

        def choice_exists(event, command)
          failure(
            :agent_choice_already_exists,
            "AgentChoice already exists",
            choice_id: command.choice_id,
            recorded_event: event.to_h
          )
        end

        def attempt_failure(code, message, command)
          failure(
            code,
            message,
            change_set_id: command.context.change_set_id,
            work_item_id: command.context.work_item_id,
            attempt_id: command.context.attempt_id
          )
        end

        def failure(code, message, **details)
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
