# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class VerificationObligationInvalidationHistory < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Domain::VerificationObligationInvalidations::State))
        required(:obligation_id).filled(:string)
      end

      rule(:state, :obligation_id) do
        state = values[:state]
        obligation_id = values[:obligation_id]
        if state.absent?
          facts = [ state.satisfied, state.failed, state.waived, state.invalidated ]
          key(:state).failure("must not contain lifecycle facts without an obligation") if facts.any?
          next
        end

        key(:state).failure("must contain the exact revision-0 obligation") unless creation?(state, obligation_id)
        key(:state).failure("must contain coherent lifecycle facts") unless lifecycle?(state, obligation_id)
      end

      private

      def creation?(state, obligation_id)
        reference = state.obligation_event
        state.obligation.obligation_id == obligation_id &&
          reference&.type == "VerificationObligationCreated" &&
          same_stream?(reference, obligation_id) && reference.stream_revision.zero?
      end

      def lifecycle?(state, obligation_id)
        pairs = [
          [ state.satisfied, state.satisfied_event, "VerificationObligationSatisfied" ],
          [ state.failed, state.failed_event, "VerificationObligationFailed" ],
          [ state.waived, state.waived_event, "VerificationObligationWaived" ],
          [ state.invalidated, state.invalidated_event, "VerificationObligationInvalidated" ]
        ]
        pairs.all? do |payload, reference, type|
          if payload
            payload.obligation_id == obligation_id && payload.obligation_event == state.obligation_event &&
              reference&.type == type && same_stream?(reference, obligation_id)
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
