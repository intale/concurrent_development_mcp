# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationWaivers
      class State < Value
        attribute :obligation, Types.Instance(Events::VerificationObligationCreatedV1).optional
        attribute :obligation_event, Types.Instance(EventReference).optional
        attribute :satisfied, Types.Instance(Events::VerificationObligationSatisfiedV1).optional
        attribute :satisfied_event, Types.Instance(EventReference).optional
        attribute :failed, Types.Instance(Events::VerificationObligationFailedV1).optional
        attribute :failed_event, Types.Instance(EventReference).optional
        attribute :waived, Types.Instance(Events::VerificationObligationWaivedV1).optional
        attribute :waived_event, Types.Instance(EventReference).optional
        attribute :invalidated, Types.Instance(Events::VerificationObligationInvalidatedV1).optional
        attribute :invalidated_event, Types.Instance(EventReference).optional
        attribute :policy_current, Types::Bool

        def self.initial
          new(
            obligation: nil,
            obligation_event: nil,
            satisfied: nil,
            satisfied_event: nil,
            failed: nil,
            failed_event: nil,
            waived: nil,
            waived_event: nil,
            invalidated: nil,
            invalidated_event: nil,
            policy_current: false
          )
        end

        def absent? = obligation.nil?

        def status
          return "invalidated" if invalidated
          return "waived" if waived
          return "satisfied" if satisfied
          return "failed" if failed

          "open"
        end

        def previous_terminal_event
          failed_event || satisfied_event
        end
      end
    end
  end
end
