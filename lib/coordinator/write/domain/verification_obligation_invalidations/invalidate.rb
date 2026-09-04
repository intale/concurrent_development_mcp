# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationInvalidations
      class Invalidate
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, superseding_partition:)
          denial = denied(state, command, superseding_partition)
          return Failure(denial) if denial

          event = Events::VerificationObligationInvalidatedV2.new(
            obligation_id: command.obligation_id,
            reason: "policy_partition_advanced"
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

        def denied(state, command, superseding_partition)
          return error(:verification_obligation_not_found, "Verification obligation does not exist", command) if state.absent?
          return error(:verification_obligation_already_invalidated, "Verification obligation is already invalidated", command) if state.invalidated
          unless state.obligation_event == command.obligation_event
            return error(:verification_obligation_changed, "Verification obligation reference does not match", command)
          end
          return if stale_policy_partition?(state, superseding_partition)

          error(
            :verification_obligation_policy_still_current,
            "Verification obligation policy partition has not advanced",
            command
          )
        end

        def stale_policy_partition?(state, superseding_partition)
          previous = state.obligation.policy.partition_event
          current = superseding_partition.reference
          previous.stream_context == current.stream_context &&
            previous.stream_name == current.stream_name &&
            previous.stream_id == current.stream_id &&
            previous.stream_revision < current.stream_revision
        end

        def error(code, message, command)
          OutcomeError.new(
            code:,
            message:,
            details: { obligation_id: command.obligation_id }
          )
        end
      end
    end
  end
end
