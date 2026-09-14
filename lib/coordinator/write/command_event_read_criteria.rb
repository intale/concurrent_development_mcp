# frozen_string_literal: true

module Coordinator::Write
  class CommandEventReadCriteria < Value
    CONTROL_EVENT_ALLOWANCE = 4

    attribute :command_id, Types::UuidV7
    attribute :through_global_position, Types::GlobalPosition
    attribute :maximum_count, Types::Integer.constrained(gteq: 0)

    def marker
      "command:#{command_id}"
    end

    def query_max_count
      maximum_count + CONTROL_EVENT_ALLOWANCE + 1
    end
  end
end
