# frozen_string_literal: true

module Coordinator::Write
  class MergeSnapshotVerificationDecisionPreparationV1 < Value
    attribute :selected_event_id, Types::UuidV7
    attribute :verified_event_id, Types::UuidV7
    attribute :correlation_id, Types::UuidV7
  end
end
