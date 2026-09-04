# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationClaimEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::VerificationObligationClaims::State))
        required(:command).value(Types.Instance(Commands::ClaimVerificationObligation))
        required(:claim_id).filled(:string)
        required(:claimed_at).filled(:string)
      end

      rule(:plan, :state, :command, :claim_id, :claimed_at) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        event = plan.events.first
        expected_stream = StreamFactory.new.verification_obligation(command.obligation_id)
        expected_expiry = (Time.iso8601(values[:claimed_at]) + command.claim_duration_seconds).utc.iso8601(6)

        valid = plan.writes.length == 1 &&
          plan.writes.first.stream == expected_stream &&
          event.is_a?(Events::VerificationObligationClaimedV2) &&
          event.obligation_id == command.obligation_id &&
          event.claim_id == values[:claim_id] &&
          event.claimant_id == command.actor.id &&
          event.fencing_token == state.next_fencing_token &&
          event.expires_at == expected_expiry

        key(:plan).failure("must contain one coherent fenced VerificationObligation claim") unless valid
      end
    end
  end
end
