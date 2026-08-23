# frozen_string_literal: true

module Coordinator::Read
  class CandidatePageV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :items, Types::Array.of(CandidateSummaryV1).constrained(max_size: 100)
    attribute :next_global_position, Types::GlobalPosition.optional
    attribute :has_more, Types::Bool
  end
end
