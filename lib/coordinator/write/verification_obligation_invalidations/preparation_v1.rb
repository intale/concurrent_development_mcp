# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationInvalidations
    class PreparationV1 < Value
      attribute :invalidated_at, Types::Timestamp
      attribute :event_id, Types::UuidV7
    end
  end
end
