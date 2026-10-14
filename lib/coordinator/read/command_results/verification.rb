# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Verification
      TOOLS = %w[verification_obligation_claim compatibility_assessment_submit verification_obligation_waive].freeze

      def call(source)
        data, summary = case source.tool_name
        when "verification_obligation_claim"
          event = source.event("VerificationObligationClaimed")
          [ source.data(event).slice(:obligation_id, :claim_id, :claimant_id, :fencing_token, :expires_at)
              .merge(claimed_at: source.timestamp(event), claim_event: source.reference(event)),
            "Verification obligation claimed for temporary exclusive coordination." ]
        when "compatibility_assessment_submit"
          event = source.event("VerificationEvidenceSubmitted")
          fact = source.data(event)
          [ fact.slice(:obligation_id, :evidence_id, :evidence_kind).merge(
              conclusion: fact.fetch(:assessment).fetch(:conclusion), status: "open",
              assessment_input_digest: event.metadata.fetch("assessment_input_digest"), evidence_event: source.reference(event),
              outcome_event: nil, submitted_at: source.timestamp(event)
            ), "Compatibility evidence accepted; verification obligation remains open." ]
        when "verification_obligation_waive"
          event = source.event("VerificationObligationWaived")
          [ source.data(event).slice(:obligation_id, :reason).merge(previous_status: "open", status: "waived",
              waiver_event: source.reference(event), waived_at: source.timestamp(event)),
            "Exact verification obligation waived by user-attributed coordination decision." ]
        end
        source.presentation(summary, data, next_actions: [ source.action("verification_obligations_list", **source.values(:obligation_id)) ])
      end
    end
  end
end
