# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class SubmissionState < Value
        IntentionObservation = Types.Instance(WorkIntentionObservationV1)

        attribute :existing_candidate, EventReference.optional
        attribute :existing_head, EventReference.optional
        attribute :attempt, Types.Instance(Attempts::State)
        attribute :intention_set, Types.Instance(WorkIntentions::SetState).optional
        attribute :current_intentions,
                  Types::Array.of(IntentionObservation).constrained(max_size: WorkIntentionPolicyV1::MAXIMUM_SET_SIZE)
      end
    end
  end
end
