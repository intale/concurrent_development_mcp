# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class StartPreparationV1 < Value
      attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(size: 2)
      attribute :correlation_id, Types::UuidV7
    end
  end
end
