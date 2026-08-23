# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactAssessment < Dry::Validation::Contract
      REASONS_BY_OUTCOME = {
        "still_valid" => %w[compliant_or_advisory noncompliance_preceded_change],
        "invalidated" => Types::AGENT_CHOICE_INVALIDATION_REASONS,
        "not_applicable" => %w[attempt_not_active change_already_observed],
        "already_invalidated" => %w[choice_terminal]
      }.freeze

      params do
        required(:assessment).value(Types.Instance(AgentChoiceImpacts::AssessmentV1))
      end

      rule(:assessment) do
        assessment = value
        unless REASONS_BY_OUTCOME.fetch(assessment.outcome).include?(assessment.reason)
          key.failure("reason must belong to the assessment outcome")
        end
        if assessment.before_context_digest == assessment.after_context_digest
          key.failure("exact before and after contexts must differ")
        end

        advancements = assessment.source_advancements
        exact = advancements.all? do |reference|
          reference.type == "DecisionPartitionAdvanced" &&
            reference.stream_context == "HumanGuidance" &&
            reference.stream_name == "DecisionPartition"
        end
        unique_and_ordered = advancements.map(&:stream_id).uniq.length == advancements.length &&
                             advancements == advancements.sort_by { _1.stream_id.b }
        key.failure("source advancements must be exact, unique, and byte-ordered") unless exact && unique_and_ordered

        case assessment.reason
        when "compliant_or_advisory"
          unless assessment.before_evaluation.status == "allowed" &&
                 assessment.after_evaluation.status == "allowed"
            key.failure("compliant impact requires allowed before and after evaluations")
          end
        when "noncompliance_preceded_change"
          if assessment.before_evaluation.status == "allowed"
            key.failure("preceding noncompliance requires a non-allowed before evaluation")
          end
        when *Types::AGENT_CHOICE_INVALIDATION_REASONS
          unless assessment.before_evaluation.status == "allowed" &&
                 assessment.after_evaluation.status != "allowed"
            key.failure("invalidation requires an allowed-to-non-allowed transition")
          end
        end
      end
    end
  end
end
