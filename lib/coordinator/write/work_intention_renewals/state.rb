# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class State < Value
      attribute :request, Types.Instance(Events::OptimisticSagas::WorkIntentionSetRenewalRequestedV1).optional.default(nil)
      attribute :assignments, Types::Array.of(Events::OptimisticSagas::WorkIntentionRenewalAssignedV1).constrained(max_size: 32).default([].freeze)
      attribute :outcomes, Types::Array.of(
        Types.Instance(Events::OptimisticSagas::WorkIntentionRenewalCompletedV1) |
        Types.Instance(Events::OptimisticSagas::WorkIntentionRenewalFailedV1)
      ).constrained(max_size: 32).default([].freeze)
      attribute :terminal, (
        Types.Instance(Events::OptimisticSagas::WorkIntentionSetRenewalCompletedV1) |
        Types.Instance(Events::OptimisticSagas::WorkIntentionSetRenewalFailedV1)
      ).optional.default(nil)

      def self.reduce(events)
        events.reduce(new) { |state, event| state.apply(event) }
      end

      def apply(event)
        changes = case event
        when Events::OptimisticSagas::WorkIntentionSetRenewalRequestedV1 then { request: event }
        when Events::OptimisticSagas::WorkIntentionRenewalAssignedV1 then { assignments: assignments + [ event ] }
        when Events::OptimisticSagas::WorkIntentionRenewalCompletedV1, Events::OptimisticSagas::WorkIntentionRenewalFailedV1
          { outcomes: outcomes + [ event ] }
        when Events::OptimisticSagas::WorkIntentionSetRenewalCompletedV1, Events::OptimisticSagas::WorkIntentionSetRenewalFailedV1
          { terminal: event }
        else {}
        end
        self.class.new(attributes.merge(changes))
      end

      def outcome(intention_id)
        outcomes.find { _1.intention_id == intention_id }
      end

      def pending
        assignments.reject { outcome(_1.intention_id) }
      end

      def failed_member
        outcomes.find { _1.is_a?(Events::OptimisticSagas::WorkIntentionRenewalFailedV1) }
      end

      def effects_committed?
        outcomes.any? { _1.is_a?(Events::OptimisticSagas::WorkIntentionRenewalCompletedV1) && _1.renewal_event }
      end
    end
  end
end
