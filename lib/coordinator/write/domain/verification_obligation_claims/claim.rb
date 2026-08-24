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
          return already_claimed(state, command) if state.active_at?(claimed_at)

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

        def already_claimed(state, command)
          claim = state.claim
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
      end
    end
  end
end
