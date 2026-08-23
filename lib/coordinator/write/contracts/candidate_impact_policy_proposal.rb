# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPolicyProposal < Dry::Validation::Contract
      TOPIC_ID = "candidate.impact_policy"
      GATE_LEVELS = %w[verification_gate merge_gate].freeze

      params do
        required(:decision).value(Types.Instance(Interpretations::SubmittedDecisionV1))
      end

      rule(:decision) do
        decision = value
        unless decision.topic_id == TOPIC_ID
          if decision.enforcement.level == "disabled"
            key([ :decision, :enforcement, :level ]).failure("disabled is reserved for candidate.impact_policy")
          end
          next
        end

        key([ :decision, :statement_kind ]).failure("must be directive") unless decision.statement_kind == "directive"
        key([ :decision, :effect ]).failure("must be require") unless decision.effect == "require"
        key([ :decision, :modality ]).failure("must be must") unless decision.modality == "must"
        report = ->(path, message) { key(path).failure(message) }
        validate_value(decision.value, report)
        validate_scope(decision.scope, report)
        validate_conditions(decision.conditions, report)
        validate_validity(decision.validity, report)
        validate_enforcement(decision.enforcement, report)
      end

      private

      def validate_value(value, report)
        report.call([ :decision, :value, :schema ], "must be string-set/v1") unless value.schema == "string-set/v1"
        %i[name target_kind target_id action].each do |field|
          report.call([ :decision, :value, field ], "must be null") unless value.public_send(field).nil?
        end

        items = value.items || []
        unless (1..8).cover?(items.length) && items.uniq.length == items.length
          report.call([ :decision, :value, :items ], "must contain 1..8 distinct evidence kinds")
        end
        invalid = items - Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS
        unless invalid.empty?
          report.call(
            [ :decision, :value, :items ],
            "contains unsupported evidence kinds: #{invalid.sort.join(", ")}"
          )
        end
      end

      def validate_scope(scope, report)
        unless scope
          report.call([ :decision, :scope ], "must identify exactly one change_set_id")
          return
        end

        report.call([ :decision, :scope, :change_set_id ], "must be present") unless scope.change_set_id
        %i[workspace_id work_item_id attempt_id candidate_id].each do |field|
          report.call([ :decision, :scope, field ], "must be null") unless scope.public_send(field).nil?
        end
        %i[
          repository_ids branch_selectors path_selectors symbol_selectors contract_selectors
          schema_selectors environments agent_roles
        ].each do |field|
          report.call([ :decision, :scope, field ], "must be empty") unless scope.public_send(field).empty?
        end
      end

      def validate_conditions(conditions, report)
        conditions.to_h.each do |field, values|
          report.call([ :decision, :conditions, field ], "must be empty") unless values.empty?
        end
      end

      def validate_validity(validity, report)
        report.call([ :decision, :validity, :valid_from ], "must be null") unless validity.valid_from.nil?
        report.call([ :decision, :validity, :valid_until ], "must be null") unless validity.valid_until.nil?
        report.call([ :decision, :validity, :until_event ], "must be null") unless validity.until_event.nil?
      end

      def validate_enforcement(enforcement, report)
        unless Types::CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS.include?(enforcement.level)
          report.call(
            [ :decision, :enforcement, :level ],
            "is not supported by candidate.impact_policy"
          )
        end
        unless enforcement.retroactivity == "all_unmerged_candidates"
          report.call(
            [ :decision, :enforcement, :retroactivity ],
            "must be all_unmerged_candidates"
          )
        end

        expected_action = GATE_LEVELS.include?(enforcement.level) ? "block" : "warn"
        unless enforcement.on_violation == expected_action
          report.call([ :decision, :enforcement, :on_violation ], "must be #{expected_action}")
        end
      end
    end
  end
end
