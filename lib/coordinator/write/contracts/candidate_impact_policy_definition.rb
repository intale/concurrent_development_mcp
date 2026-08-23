# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateImpactPolicyDefinition < Dry::Validation::Contract
      TOPIC = Interpretations::TopicRegistry.new.fetch("candidate.impact_policy")
      GATE_LEVELS = %w[verification_gate merge_gate].freeze

      params do
        required(:definition).value(Types.Instance(Decisions::DecisionDefinitionV1))
        required(:change_set_id).filled(:string)
        required(:expected_digest).value(Types::Sha256Digest)
      end

      rule(:definition, :change_set_id, :expected_digest) do
        definition = values[:definition]
        document = definition.document
        report = ->(field, message) { key([ :definition, field ]).failure(message) }
        report.call(:digest, "must match canonical definition content") unless definition.digest == values[:expected_digest]
        report.call(:topic, "must be the exact candidate.impact_policy ontology") unless document.topic == TOPIC
        report.call(:statement_kind, "must be directive") unless document.statement_kind == "directive"
        report.call(:effect, "must be require") unless document.effect == "require"
        report.call(:modality, "must be must") unless document.modality == "must"
        validate_value(document.value, report)
        validate_scope(document.scope, values[:change_set_id], report)
        validate_conditions(document.conditions, report)
        validate_validity(document.validity, report)
        validate_enforcement(document.enforcement, report)
      end

      private

      def validate_value(value, report)
        valid = value.schema == "string-set/v1" && value.name.nil? && value.target_kind.nil? &&
                value.target_id.nil? && value.action.nil?
        report.call(:value, "must be a string-set/v1 evidence requirement") unless valid
        items = value.items || []
        unless (1..8).cover?(items.length) && items == items.uniq.sort_by(&:b) &&
               (items - Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS).empty?
          report.call(:value, "must contain sorted distinct supported evidence kinds")
        end
      end

      def validate_scope(scope, change_set_id, report)
        scalars = scope.workspace_id.nil? && scope.work_item_id.nil? && scope.attempt_id.nil? &&
                  scope.candidate_id.nil? && scope.change_set_id == change_set_id
        collections = %i[
          repository_ids branch_selectors path_selectors symbol_selectors contract_selectors
          schema_selectors environments agent_roles
        ].all? { scope.public_send(_1).empty? }
        report.call(:scope, "must identify only the exact ChangeSet") unless scalars && collections
      end

      def validate_conditions(conditions, report)
        report.call(:conditions, "must be empty") unless conditions.to_h.values.all?(&:empty?)
      end

      def validate_validity(validity, report)
        valid = validity.valid_from && validity.valid_until.nil? && validity.until_event.nil?
        report.call(:validity, "must start at activation/correction without expiry") unless valid
      end

      def validate_enforcement(enforcement, report)
        level = enforcement.level
        valid_level = Types::CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS.include?(level)
        expected_action = GATE_LEVELS.include?(level) ? "block" : "warn"
        valid = valid_level && enforcement.retroactivity == "all_unmerged_candidates" &&
                enforcement.on_violation == expected_action
        report.call(:enforcement, "must use the exact impact-policy enforcement tuple") unless valid
      end
    end
  end
end
