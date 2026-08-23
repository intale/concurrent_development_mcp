# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoices
      class PolicyEvaluator
        POSITIVE_EFFECTS = %w[require prefer select approve prioritize].freeze
        NEGATIVE_EFFECTS = %w[forbid avoid reject].freeze

        def call(resolution:, selected_option_id:)
          return unsupported(resolution) unless resolution.unsupported_dimensions.empty?
          return unresolved(resolution) unless resolution.unresolved_decisions.empty?
          return conflict(resolution) if resolution.conflict

          decision = resolution.effective_decision
          return no_policy unless decision
          return unsupported_effective(decision) unless named_choice?(decision)
          return compliant(decision) unless violation?(decision, selected_option_id)

          violation(decision)
        end

        private

        def named_choice?(decision)
          decision.value.schema == "named-choice/v1" && decision.value.name
        end

        def violation?(decision, selected_option_id)
          if POSITIVE_EFFECTS.include?(decision.effect)
            selected_option_id != decision.value.name
          elsif NEGATIVE_EFFECTS.include?(decision.effect)
            selected_option_id == decision.value.name
          else
            false
          end
        end

        def violation(decision)
          case decision.enforcement.on_violation
          when "warn"
            evaluation(
              status: "allowed",
              decision:,
              basis: "advisory_violation",
              warnings: [ "decision-warning:#{decision.head.decision_id}:#{decision.head.event.event_id}" ],
              reason_codes: [ "selected_option_violates_advisory_decision" ]
            )
          when "block", "block_and_replan"
            evaluation(
              status: "blocked",
              decision:,
              basis: "blocking_violation",
              reason_codes: [ "selected_option_violates_blocking_decision" ]
            )
          when "require_confirmation"
            evaluation(
              status: "confirmation_required",
              decision:,
              basis: "confirmation_required",
              reason_codes: [ "selected_option_requires_confirmation" ]
            )
          end
        end

        def no_policy
          Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
            status: "allowed",
            effective_decision: nil,
            contributing_decisions: [],
            basis: "no_policy",
            warnings: [],
            reason_codes: [ "no_active_decision" ]
          )
        end

        def compliant(decision)
          evaluation(
            status: "allowed",
            decision:,
            basis: "compliant",
            reason_codes: [ "selected_option_satisfies_decision" ]
          )
        end

        def unsupported(resolution)
          Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
            status: "unsupported",
            effective_decision: nil,
            contributing_decisions: resolution.unsupported_decisions,
            basis: "unsupported_context",
            warnings: [],
            reason_codes: [ "unsupported_decision_context" ]
          )
        end

        def unsupported_effective(decision)
          evaluation(
            status: "unsupported",
            decision:,
            basis: "unsupported_context",
            reason_codes: [ "unsupported_decision_context" ]
          )
        end

        def unresolved(resolution)
          Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
            status: "unresolved",
            effective_decision: nil,
            contributing_decisions: resolution.unresolved_decisions,
            basis: "unresolved_head",
            warnings: [],
            reason_codes: [ "unresolved_decision_head" ]
          )
        end

        def conflict(resolution)
          heads = resolution.conflict.decisions.map(&:head)
          Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
            status: "conflict",
            effective_decision: nil,
            contributing_decisions: heads,
            basis: "decision_conflict",
            warnings: [],
            reason_codes: [ "tied_most_specific_decisions" ]
          )
        end

        def evaluation(status:, decision:, basis:, reason_codes:, warnings: [])
          Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
            status:,
            effective_decision: decision.head,
            contributing_decisions: [ decision.head ],
            basis:,
            warnings:,
            reason_codes:
          )
        end
      end
    end
  end
end
