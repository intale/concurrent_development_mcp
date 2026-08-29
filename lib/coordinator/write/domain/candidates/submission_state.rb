# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class SubmissionState < Value
        LeaseObservation = Types.Instance(CurrentLeaseObservationV1) |
                           Types.Instance(CurrentLeaseObservationV2)

        attribute :existing_candidate, EventReference.optional
        attribute :existing_head, EventReference.optional
        attribute :attempt, Types.Instance(Attempts::State)
        attribute :current_leases,
                  Types::Array.of(LeaseObservation).constrained(max_size: 32)
      end
    end
  end
end
