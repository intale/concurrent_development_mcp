# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationEvidenceProjection < Dry::Validation::Contract
      params do
        required(:obligation).value(Types.Instance(Coordinator::Write::Events::VerificationObligationCreatedV1))
        required(:obligation_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:claim).value(Types.Instance(Coordinator::Write::Events::VerificationObligationClaimedV1))
        required(:claim_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:submission).value(Types.Instance(Coordinator::Write::Events::VerificationEvidenceSubmittedV1))
        required(:submission_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:actor_id).filled(:string)
        required(:current_status).filled(:string, eql?: "open")
        required(:evidence_count).filled(
          :integer,
          gteq?: 0,
          lt?: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT
        )
      end

      rule do
        key(:submission).failure("must match the exact projected obligation and claim") unless coherent?(values)
      end

      private

      def coherent?(values)
        obligation = values[:obligation]
        obligation_event = values[:obligation_event]
        claim = values[:claim]
        claim_event = values[:claim_event]
        submission = values[:submission]
        submission_event = values[:submission_event]
        claim_evidence = submission.claim

        submission.obligation_id == obligation.obligation_id &&
          submission.obligation_event == obligation_event &&
          claim.obligation_id == obligation.obligation_id &&
          claim.obligation_event == obligation_event &&
          claim_evidence.claim_id == claim.claim_id &&
          claim_evidence.claimant_id == claim.claimant_id &&
          claim_evidence.fencing_token == claim.fencing_token &&
          claim_evidence.claim_event == claim_event &&
          values[:actor_id] == claim.claimant_id &&
          submission.source_candidate == obligation.source_candidate &&
          submission.target_candidate == obligation.target_candidate &&
          submission.policy == obligation.policy &&
          submission.obligation_validity_input_digest == obligation.validity_input_digest &&
          submission.evidence_kind == submission.assessment.evidence_kind &&
          submission_event.type == "VerificationEvidenceSubmitted" &&
          same_stream?(submission_event, obligation.obligation_id) &&
          submission_event.stream_revision > claim_event.stream_revision
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id
      end
    end
  end
end
