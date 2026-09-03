# frozen_string_literal: true

module Coordinator::Write
  module CommandLifecycle
    class Transition < Value
      attribute :state, Types.Instance(Domain::CommandLifecycles::State)
      attribute :terminal_event, Types.Instance(PgEventstore::Event)
    end
  end
end
