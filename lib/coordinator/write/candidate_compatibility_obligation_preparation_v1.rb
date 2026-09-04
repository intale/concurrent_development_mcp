# frozen_string_literal: true

module Coordinator::Write
  class CandidateCompatibilityObligationPreparationV1 < Value
    attribute :created_at, Types::Timestamp
    attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(size: 4)
  end
end
