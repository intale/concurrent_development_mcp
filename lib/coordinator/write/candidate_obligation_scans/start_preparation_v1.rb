# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class StartPreparationV1 < Value
      attribute :observed_at, Types::Timestamp
      attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 2, max_size: 4)
      attribute :correlation_id, Types::UuidV7
    end
  end
end
