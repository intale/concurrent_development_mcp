# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationClaimHistory < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Domain::VerificationObligationClaims::State))
        required(:obligation_id).filled(:string)
      end

      rule(:state, :obligation_id) do
        state = values[:state]
        obligation_id = values[:obligation_id]
        if state.absent?
          valid = state.obligation_event.nil? && state.claim.nil? && !state.terminal?
          key(:state).failure("must not contain a claim without an obligation") unless valid
          next
        end

        obligation = state.obligation
        reference = state.obligation_event
        valid_creation = !obligation.nil? &&
          obligation.obligation_id == obligation_id &&
          reference&.type == "VerificationObligationCreated" &&
          reference&.stream_context == "DevelopmentIntegration" &&
          reference&.stream_name == "VerificationObligation" &&
          reference&.stream_id == obligation_id &&
          reference&.stream_revision == 0
        unless valid_creation
          key(:state).failure("must contain the exact revision-0 obligation creation")
          next
        end

        claim = state.claim
        if claim
          valid_claim = claim.obligation_id == obligation_id &&
            claim.obligation_event == reference &&
            claim.claimed_at < claim.expires_at
          key(:state).failure("must contain one coherent latest claim") unless valid_claim
        end

        if state.terminal?
          valid_terminal = state.terminal_status != "open" &&
            state.terminal_event&.stream_context == "DevelopmentIntegration" &&
            state.terminal_event&.stream_name == "VerificationObligation" &&
            state.terminal_event&.stream_id == obligation_id
          key(:state).failure("must contain one coherent terminal lifecycle reference") unless valid_terminal
        end
      end
    end
  end
end
