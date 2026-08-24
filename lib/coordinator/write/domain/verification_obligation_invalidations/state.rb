# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationInvalidations
      class State < Value
        attribute :obligation, Types.Instance(Events::VerificationObligationCreatedV1).optional
        attribute :obligation_event, EventReference.optional
        attribute :satisfied, Types.Instance(Events::VerificationObligationSatisfiedV1).optional
        attribute :satisfied_event, EventReference.optional
        attribute :failed, Types.Instance(Events::VerificationObligationFailedV1).optional
        attribute :failed_event, EventReference.optional
        attribute :waived, Types.Instance(Events::VerificationObligationWaivedV1).optional
        attribute :waived_event, EventReference.optional
        attribute :invalidated, Types.Instance(Events::VerificationObligationInvalidatedV1).optional
        attribute :invalidated_event, EventReference.optional

        def absent? = obligation.nil?

        def status
          return "invalidated" if invalidated
          return "waived" if waived
          return "satisfied" if satisfied
          return "failed" if failed

          "open"
        end

        def previous_terminal_event
          waived_event || satisfied_event || failed_event
        end
      end
    end
  end
end
