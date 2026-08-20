# frozen_string_literal: true

module Coordinator
  class OperationGetQueryV1 < Value
    attribute :command_id, Types::Identifier
    attribute :projections, Types::Array.of(Types::String.enum("coord_context_v1")).constrained(min_size: 1, max_size: 10)
  end
end
