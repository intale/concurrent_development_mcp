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
            !state.policy_current
          key(:state).failure("must not contain verification history without an obligation") unless valid
          next
        end

        unless coherent_creation?(state, obligation_id)
          key(:state).failure("must contain the exact revision-0 obligation creation")
          next
        end
        key(:state).failure("must contain one coherent latest claim") unless coherent_claim?(state, obligation_id)
        key(:state).failure("must contain coherent evidence observations") unless coherent_evidence?(state, obligation_id)
        key(:state).failure("must contain at most one coherent terminal outcome") unless coherent_terminal?(state, obligation_id)
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
          claim.obligation_event == state.obligation_event &&
          claim.claimed_at < claim.expires_at &&
          reference&.type == "VerificationObligationClaimed" &&
          same_stream?(reference, obligation_id)
      end

      def coherent_evidence?(state, obligation_id)
        digests = state.evidence.map { _1.evidence.assessment_input_digest }
        return false unless digests.uniq.length == digests.length
        revisions = state.evidence.map { _1.event.stream_revision }
        return false unless revisions == revisions.sort && revisions.uniq.length == revisions.length

        state.evidence.all? do |observation|
          evidence = observation.evidence
          reference = observation.event
          evidence.obligation_id == obligation_id &&
            evidence.obligation_event == state.obligation_event &&
            evidence.evidence_kind == evidence.assessment.evidence_kind &&
            evidence.obligation_validity_input_digest == state.obligation.validity_input_digest &&
            evidence.source_candidate == state.obligation.source_candidate &&
            evidence.target_candidate == state.obligation.target_candidate &&
            evidence.policy == state.obligation.policy &&
            reference.event_id == evidence.evidence_id &&
            reference.type == "VerificationEvidenceSubmitted" &&
            same_stream?(reference, obligation_id)
        end
      end

      def coherent_terminal?(state, obligation_id)
        return false if state.satisfied && state.failed
        return true unless state.terminal?

        terminal = state.satisfied || state.failed
        common = terminal.obligation_id == obligation_id &&
          terminal.obligation_event == state.obligation_event &&
          terminal.policy == state.obligation.policy
        return false unless common

        if state.satisfied
          coherent_satisfaction?(state)
        else
          coherent_failure?(state)
        end
      end

      def coherent_satisfaction?(state)
        selected = state.satisfied.selected_evidence
        observations = state.evidence.map(&:decision_reference)
        required = state.obligation.required_evidence
        selected.map(&:evidence_kind) == required &&
          selected.all? { _1.conclusion == "passed" && observations.include?(_1) } &&
          state.satisfied.outcome_digest == CompatibilityAssessments::OutcomeDigestBuilder.new.satisfied(
            obligation: state.obligation,
            selected_evidence: selected
          )
      end

      def coherent_failure?(state)
        triggering = state.failed.triggering_evidence
        state.evidence.map(&:decision_reference).include?(triggering) &&
          triggering.conclusion == "failed" &&
          state.failed.outcome_digest == CompatibilityAssessments::OutcomeDigestBuilder.new.failed(
            obligation: state.obligation,
            triggering_evidence: triggering
          )
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id
      end
    end
  end
end
