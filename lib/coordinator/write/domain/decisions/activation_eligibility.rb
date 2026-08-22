# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class ActivationEligibility
        include Dry::Monads[:result]

        NON_NORMATIVE_KINDS = %w[question hypothesis].freeze

        def initialize(topic_registry: Coordinator::Write::Interpretations::TopicRegistry.new)
          @topic_registry = topic_registry
        end

        def call(proposal:, activated_at:)
          decision = proposal.proposed_decision
          reasons = []
          reasons << "non_normative_statement_kind" if NON_NORMATIVE_KINDS.include?(decision.statement_kind)
          reasons << "missing_effect" unless decision.effect
          reasons << "missing_modality" unless decision.modality
          reasons << "scope_unresolved" unless concrete_scope?(decision.scope)
          reasons << "lifecycle_relation_requires_specific_command" if lifecycle_relation?(decision.relations)
          reasons << "until_event_requires_expiry_policy" if decision.validity.until_event
          reasons << "validity_elapsed" if elapsed?(decision.validity, activated_at)
          reasons << "topic_registry_mismatch" unless @topic_registry.fetch(decision.topic_id)
          return denied(reasons) unless reasons.empty?

          Success()
        end

        private

        def concrete_scope?(scope)
          scope.workspace_id ||
            !scope.repository_ids.empty? ||
            scope.change_set_id ||
            scope.work_item_id ||
            scope.attempt_id ||
            scope.candidate_id
        end

        def lifecycle_relation?(relations)
          relations.to_h.values.any? { !_1.empty? }
        end

        def elapsed?(validity, activated_at)
          valid_from = validity.valid_from || activated_at
          validity.valid_until &&
            (validity.valid_until <= valid_from || validity.valid_until <= activated_at)
        end

        def denied(reasons)
          Failure(
            OutcomeError.new(
              code: :decision_definition_not_activatable,
              message: "Accepted interpretation cannot be activated by version 1 policy",
              details: { reasons: }
            )
          )
        end
      end
    end
  end
end
