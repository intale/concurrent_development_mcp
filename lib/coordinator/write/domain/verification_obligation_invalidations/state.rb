# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationInvalidations
      class State < Value
        attribute :obligation, Types.Instance(VerificationObligations::DefinitionV2).optional
        attribute :obligation_event, EventReference.optional
        attribute :satisfied, Types.Instance(Events::VerificationObligationSatisfiedV2).optional
        attribute :satisfied_event, EventReference.optional
        attribute :failed, Types.Instance(Events::VerificationObligationFailedV2).optional
        attribute :failed_event, EventReference.optional
        attribute :waived, Types.Instance(Events::VerificationObligationWaivedV2).optional
        attribute :waived_event, EventReference.optional
        attribute :invalidated, Types.Instance(Events::VerificationObligationInvalidatedV2).optional
        attribute :invalidated_event, EventReference.optional

        def absent? = obligation.nil?

        def status
          return "invalidated" if invalidated
          return "waived" if waived
          return "satisfied" if satisfied
          return "failed" if failed

          "open"
        end

        def previous_terminal_event = waived_event || satisfied_event || failed_event
      end
    end
  end
end
