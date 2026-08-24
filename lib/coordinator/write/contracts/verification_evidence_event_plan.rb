# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationEvidenceEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationEvidence::State))
        required(:command).value(Types.Instance(Commands::SubmitCompatibilityAssessment))
        required(:evidence_id).filled(:string)
        required(:assessment_input_digest).filled(:string)
        required(:evidence_event).value(Types.Instance(EventReference))
        required(:submitted_at).filled(:string)
      end

      rule(:plan, :state, :command, :evidence_id, :assessment_input_digest, :evidence_event, :submitted_at) do
        reference = values[:evidence_event]
        unless coherent_future_reference?(values[:state], values[:command], values[:evidence_id], reference)
          key(:evidence_event).failure("must identify the next evidence fact in the exact obligation stream")
          next
        end

        decision = Domain::VerificationEvidence::Submit.new.call(
          state: values[:state],
          command: values[:command],
          evidence_id: values[:evidence_id],
          assessment_input_digest: values[:assessment_input_digest],
          evidence_event: reference,
          submitted_at: values[:submitted_at]
        )
        valid = decision.success? && decision.value! == values[:plan]
        key(:plan).failure("must preserve the exact compatibility evidence decision") unless valid
      end

      private

      def coherent_future_reference?(state, command, evidence_id, reference)
        known_revisions = [ state.obligation_event, state.latest_claim_event, *state.evidence.map(&:event) ]
          .compact
          .map(&:stream_revision)
        reference.event_id == evidence_id &&
          reference.type == "VerificationEvidenceSubmitted" &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == command.obligation_id &&
          reference.stream_revision == known_revisions.max + 1
      end
    end
  end
end
