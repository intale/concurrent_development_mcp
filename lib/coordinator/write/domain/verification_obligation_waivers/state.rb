# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module VerificationObligationWaivers
      class State < Value
        attribute :obligation, Types.Instance(VerificationObligations::DefinitionV2).optional
        attribute :obligation_event, Types.Instance(EventReference).optional
        attribute :satisfied, Types.Instance(Events::VerificationObligationSatisfiedV2).optional
        attribute :satisfied_event, Types.Instance(EventReference).optional
        attribute :failed, Types.Instance(Events::VerificationObligationFailedV2).optional
        attribute :failed_event, Types.Instance(EventReference).optional
        attribute :waived, Types.Instance(Events::VerificationObligationWaivedV2).optional
        attribute :waived_event, Types.Instance(EventReference).optional
        attribute :invalidated, Types.Instance(Events::VerificationObligationInvalidatedV2).optional
        attribute :invalidated_event, Types.Instance(EventReference).optional

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
            invalidated_event: nil
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

      end
    end
  end
end
