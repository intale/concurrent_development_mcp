# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetExecution < Value
      attribute :command_state, Types.Instance(Domain::CommandLifecycles::State)
      attribute :terminal_event, Types.Instance(PgEventstore::Event)
    end
  end
end
