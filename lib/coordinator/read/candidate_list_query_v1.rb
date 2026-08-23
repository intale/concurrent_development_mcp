# frozen_string_literal: true

module Coordinator::Read
  class CandidateListQueryV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :after_global_position, Types::GlobalPosition.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
