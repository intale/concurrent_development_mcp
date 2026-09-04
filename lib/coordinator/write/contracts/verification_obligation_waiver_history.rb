# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationWaiverHistory < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Domain::VerificationObligationWaivers::State))
        required(:obligation_id).filled(:string)
      end

      rule(:state, :obligation_id) do
        state = values[:state]
        obligation_id = values[:obligation_id]
        if state.absent?
          lifecycle = [ state.satisfied, state.failed, state.waived, state.invalidated ]
          key(:state).failure("must not contain lifecycle facts without an obligation") if lifecycle.any?
          next
        end

        unless coherent_creation?(state, obligation_id)
          key(:state).failure("must contain the exact revision-0 obligation creation")
          next
        end
        key(:state).failure("must not contain both satisfied and failed facts") if state.satisfied && state.failed
        key(:state).failure("must contain coherent lifecycle references") unless coherent_lifecycle?(state, obligation_id)
      end

      private

      def coherent_creation?(state, obligation_id)
        obligation = state.obligation
        reference = state.obligation_event
        obligation.obligation_id == obligation_id &&
          reference&.type == "VerificationObligationCreated" &&
          same_stream?(reference, obligation_id) &&
          reference.stream_revision.zero?
      end

      def coherent_lifecycle?(state, obligation_id)
        pairs = [
          [ state.satisfied, state.satisfied_event, "VerificationObligationSatisfied" ],
          [ state.failed, state.failed_event, "VerificationObligationFailed" ],
          [ state.waived, state.waived_event, "VerificationObligationWaived" ],
          [ state.invalidated, state.invalidated_event, "VerificationObligationInvalidated" ]
        ]
        pairs.all? do |payload, reference, type|
          if payload
            payload.obligation_id == obligation_id &&
              reference&.type == type &&
              same_stream?(reference, obligation_id)
          else
            reference.nil?
          end
        end
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id
      end
    end
  end
end
