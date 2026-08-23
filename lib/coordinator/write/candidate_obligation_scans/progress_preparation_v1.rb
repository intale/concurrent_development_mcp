# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class ProgressPreparationV1 < Value
      attribute :progressed_at, Types::Timestamp
      attribute :event_id, Types::UuidV7
    end
  end
end
