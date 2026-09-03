# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Source < Value
      CommandType = Coordinator::Write::Tasks::TargetContractRegistry.command_classes
        .map { Coordinator::Shared::Types.Instance(_1) }
        .reduce { _1 | _2 }

      attribute :terminal_event, Types.Instance(PgEventstore::Event)
      attribute :command_state, Types.Instance(CommandState)
      attribute :command, CommandType
      attribute :persisted_events,
                Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 128)
      attribute :payloads,
                Types::Array.of(Types.Instance(Coordinator::Write::Events::Base)).constrained(max_size: 128)

      def completed_at
        terminal_event.created_at.utc.iso8601(6)
      end
    end
  end
end
