# frozen_string_literal: true

module Coordinator::Write
  class CandidateCompatibilityObligationPreparationV1 < Value
    attribute :created_at, Types::Timestamp
    attribute :obligation_event_id, Types::UuidV7
  end
end
