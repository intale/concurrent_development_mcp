# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class ProposalAssessment
        NON_NORMATIVE_KINDS = %w[question hypothesis].freeze
        HARD_EFFECTS = %w[require forbid reject].freeze
        HARD_MODALITIES = %w[must must_not].freeze
        HIGH_IMPACT_LEVELS = %w[merge_gate deployment_gate].freeze

        def call(command:, scope:, provenance:)
          classification_reasons = classification_reasons(command, provenance)
          return needs_classification(command, classification_reasons) unless classification_reasons.empty?

          confirmation_reasons = confirmation_reasons(command, scope)
          return confirmation_required(confirmation_reasons) unless confirmation_reasons.empty?

          Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(
            status: "accepted_for_activation",
            reasons: [],
            questions: []
          )
        end

        private

        def classification_reasons(command, provenance)
          reasons = []
          reasons << "non_normative_statement_kind" if NON_NORMATIVE_KINDS.include?(command.proposed_decision.statement_kind)
          reasons << "classifier_ambiguity" unless command.ambiguities.empty?
          reasons << "scope_unresolved" if provenance.anchor_level == "unresolved"
          reasons
        end

        def confirmation_reasons(command, scope)
          decision = command.proposed_decision
          reasons = []
          reasons << "hard_constraint" if HARD_EFFECTS.include?(decision.effect) || HARD_MODALITIES.include?(decision.modality)
          reasons << "high_impact_enforcement" if HIGH_IMPACT_LEVELS.include?(decision.enforcement.level)
          reasons << "retroactive_application" unless decision.enforcement.retroactivity == "future_only"
          reasons << "broad_scope" if broad_scope?(scope)
          reasons << "lifecycle_relation" if decision.relations.to_h.values.any? { !_1.empty? }
          reasons
        end

        def broad_scope?(scope)
          return true if scope.workspace_id

          scope.attempt_id.nil? && scope.work_item_id.nil? && scope.change_set_id.nil? && !scope.repository_ids.empty?
        end

        def needs_classification(command, reasons)
          questions = command.ambiguities.map do |ambiguity|
            Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
              field: ambiguity.field,
              prompt: ambiguity.description,
              options: ambiguity.options
            )
          end
          if reasons.include?("non_normative_statement_kind")
            questions << Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
              field: "statement_kind",
              prompt: "Classify whether this statement is normative.",
              options: %w[directive preference fact question]
            )
          end
          if reasons.include?("scope_unresolved")
            questions << Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
              field: "scope",
              prompt: "Choose the narrowest intended scope.",
              options: %w[repository change_set work_item attempt]
            )
          end

          Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(
            status: "needs_classification",
            reasons: reasons.uniq,
            questions: questions.uniq { [ _1.field, _1.prompt, _1.options ] }
          )
        end

        def confirmation_required(reasons)
          Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(
            status: "confirmation_required",
            reasons: reasons.uniq,
            questions: [
              Coordinator::Write::Interpretations::ClarificationQuestionV1.new(
                field: "confirmation",
                prompt: "Confirm or revise this high-impact interpretation.",
                options: %w[confirm revise]
              )
            ]
          )
        end
      end
    end
  end
end
