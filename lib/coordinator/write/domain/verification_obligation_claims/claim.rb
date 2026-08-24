# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationClaims
      class Claim
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, claim_id:, claimed_at:)
          return not_found(command) if state.absent? || state.obligation_event.nil?
          return terminal(state, command) if state.terminal?
          active_claim = state.active_claim_at(claimed_at)
          return already_claimed(active_claim, command) if active_claim

          expires_at = (Time.iso8601(claimed_at) + command.claim_duration_seconds).utc.iso8601(6)
          event = Events::VerificationObligationClaimedV1.new(
            obligation_id: command.obligation_id,
            obligation_event: state.obligation_event,
            claim_id:,
            claimant_id: command.actor.id,
            fencing_token: state.next_fencing_token,
            claimed_at:,
            expires_at:
          )

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.verification_obligation(command.obligation_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def not_found(command)
          Failure(
            OutcomeError.new(
              code: :verification_obligation_not_found,
              message: "Verification obligation does not exist",
              details: { obligation_id: command.obligation_id }
            )
          )
        end

        def already_claimed(claim, command)
          Failure(
            OutcomeError.new(
              code: :verification_obligation_already_claimed,
              message: "Verification obligation already has an active claim",
              details: {
                obligation_id: command.obligation_id,
                claim_id: claim.claim_id,
                claimant_id: claim.claimant_id,
                fencing_token: claim.fencing_token,
                expires_at: claim.expires_at
              }
            )
          )
        end

        def terminal(state, command)
          Failure(
            OutcomeError.new(
              code: :verification_obligation_terminal,
              message: "Verification obligation is already terminal",
              details: { obligation_id: command.obligation_id, status: state.status }
            )
          )
        end
      end
    end
  end
end
