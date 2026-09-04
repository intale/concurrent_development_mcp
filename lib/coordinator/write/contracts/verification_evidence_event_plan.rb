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
        required(:submitted_at).filled(:string)
      end

      rule(:plan, :state, :command, :evidence_id, :assessment_input_digest, :submitted_at) do
        decision = Domain::VerificationEvidence::Submit.new.call(
          state: values[:state],
          command: values[:command],
          evidence_id: values[:evidence_id],
          assessment_input_digest: values[:assessment_input_digest],
          submitted_at: values[:submitted_at]
        )
        valid = decision.success? && decision.value! == values[:plan] &&
          values[:plan].events.length == 1 &&
          values[:plan].events.sole.is_a?(Events::VerificationEvidenceSubmittedV2)
        key(:plan).failure("must preserve the exact cohesive verification-evidence decision") unless valid
      end
    end
  end
end
