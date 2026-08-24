# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationLifecycleProjection < Dry::Validation::Contract
      Transition = Types.Instance(Coordinator::Write::Events::VerificationObligationWaivedV1) |
        Types.Instance(Coordinator::Write::Events::VerificationObligationInvalidatedV1)

      params do
        required(:obligation).value(Types.Instance(Coordinator::Write::Events::VerificationObligationCreatedV1))
        required(:obligation_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:transition).value(Transition)
        required(:transition_event).value(Types.Instance(Coordinator::Write::EventReference))
        required(:current_status).filled(:string)
        optional(:current_terminal_event).maybe(Types.Instance(Coordinator::Write::EventReference))
      end

      rule do
        key(:transition).failure("must follow the exact projected lifecycle") unless coherent?(values)
      end

      private

      def coherent?(values)
        obligation = values[:obligation]
        transition = values[:transition]
        reference = values[:transition_event]
        common = transition.obligation_id == obligation.obligation_id &&
          transition.obligation_event == values[:obligation_event] &&
          transition.previous_status == values[:current_status] &&
          transition.previous_terminal_event == values[:current_terminal_event] &&
          same_stream?(reference, obligation.obligation_id)
        return false unless common

        case transition
        when Coordinator::Write::Events::VerificationObligationWaivedV1
          reference.type == "VerificationObligationWaived" &&
            transition.policy == obligation.policy && %w[open failed].include?(values[:current_status])
        when Coordinator::Write::Events::VerificationObligationInvalidatedV1
          reference.type == "VerificationObligationInvalidated" &&
            transition.invalidated_policy == obligation.policy &&
            values[:current_status] != "invalidated" && later_partition?(transition, obligation)
        else
          false
        end
      end

      def later_partition?(transition, obligation)
        prior = obligation.policy.partition_event
        current = transition.superseding_partition_event
        prior.stream_context == current.stream_context &&
          prior.stream_name == current.stream_name && prior.stream_id == current.stream_id &&
          prior.stream_revision < current.stream_revision
      end

      def same_stream?(reference, obligation_id)
        reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "VerificationObligation" &&
          reference.stream_id == obligation_id && reference.stream_revision.positive?
      end
    end
  end
end
