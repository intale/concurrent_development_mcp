# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationPageV1 < Value
    attribute :items, Types::Array.of(VerificationObligationViewV1).constrained(max_size: 100)
    attribute :next_global_position, Types::GlobalPosition.optional
    attribute :has_more, Types::Bool
    attribute :observed_at, Types::Timestamp
  end
end
