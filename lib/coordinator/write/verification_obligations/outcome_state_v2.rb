# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class OutcomeStateV2 < Value
      Observation = Types.Instance(CompatibilityAssessments::EvidenceObservationV2)

      attribute :definition, DefinitionV2
      attribute :definition_event, EventReference
      attribute :evidence, Types::Array.of(Observation).constrained(max_size: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT)
      attribute :selected_evidence_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 8)
      attribute :terminal_status, Types::VerificationObligationStatus.optional
      attribute :terminal_event, EventReference.optional
      attribute :latest_revision, Types::Integer.constrained(gteq: 0)

      def terminal? = !terminal_status.nil?

      def observation(evidence_id)
        evidence.find { _1.evidence.evidence_id == evidence_id }
      end

      def passed_by_kind
        evidence.each_with_object({}) do |item, selected|
          selected[item.evidence.evidence_kind] = item if item.evidence.assessment.conclusion == "passed"
        end.freeze
      end
    end
  end
end
