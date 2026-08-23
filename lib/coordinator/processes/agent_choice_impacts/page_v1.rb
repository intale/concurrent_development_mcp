# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class PageV1 < Value
      attribute :accepted_choices,
                Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 50)
      attribute :last_processed_position, Types::GlobalPosition.optional
      attribute :has_more, Types::Bool
    end
  end
end
