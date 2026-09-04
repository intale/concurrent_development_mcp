# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationEvidenceHistory < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Domain::VerificationEvidence::State))
        required(:obligation_id).filled(:string)
      end

      rule(:state, :obligation_id) do
        state = values[:state]
        obligation_id = values[:obligation_id]
        if state.absent?
          valid = state.obligation_event.nil? && state.latest_claim.nil? &&
            state.latest_claim_event.nil? && state.evidence.empty? && !state.terminal? &&
            !state.policy_current && !state.waived && !state.invalidated
          key(:state).failure("must not contain verification history without an obligation") unless valid
          next
        end

        key(:state).failure("must contain the exact obligation creation") unless coherent_creation?(state, obligation_id)
        key(:state).failure("must contain one coherent latest claim") unless coherent_claim?(state, obligation_id)
        key(:state).failure("must contain coherent evidence observations") unless coherent_evidence?(state, obligation_id)
        key(:state).failure("must contain at most one coherent terminal fact") unless coherent_terminal?(state, obligation_id)
      end

      private

      def coherent_creation?(state, obligation_id)
        obligation = state.obligation
        reference = state.obligation_event
        obligation.obligation_id == obligation_id &&
          reference&.type == "VerificationObligationCreated" &&
          reference&.stream_context == "DevelopmentIntegration" &&
          reference&.stream_name == "VerificationObligation" &&
          reference&.stream_id == obligation_id &&
          reference&.stream_revision == 0
      end

      def coherent_claim?(state, obligation_id)
        claim = state.latest_claim
        reference = state.latest_claim_event
        return reference.nil? unless claim

        claim.obligation_id == obligation_id &&
          reference&.type == "VerificationObligationClaimed" &&
          same_stream?(reference, obligation_id)
      end

      def coherent_evidence?(state, obligation_id)
        digests = state.evidence.map(&:assessment_input_digest)
        revisions = state.evidence.map { _1.event.stream_revision }
        return false unless digests.uniq.length == digests.length
        return false unless revisions == revisions.sort && revisions.uniq.length == revisions.length

        state.evidence.all? do |observation|
          evidence = observation.evidence
          reference = observation.event
          evidence.obligation_id == obligation_id &&
            evidence.evidence_kind == evidence.assessment.evidence_kind &&
            evidence.claim.claim_event.type == "VerificationObligationClaimed" &&
            same_stream?(evidence.claim.claim_event, obligation_id) &&
            observation.obligation_validity_input_digest == state.obligation.validity_input_digest &&
            observation.policy == state.obligation.policy &&
            reference.type == "VerificationEvidenceSubmitted" &&
            same_stream?(reference, obligation_id)
        end
      end

      def coherent_terminal?(state, obligation_id)
        terminals = [ state.satisfied, state.failed, state.waived, state.invalidated ].compact
        terminals.length <= 1 && terminals.all? { _1.obligation_id == obligation_id }
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id
      end
    end
  end
end
