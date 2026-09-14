# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CommandHistory < Dry::Validation::Contract
      params do
        required(:events).array(Types.Instance(Events::Base))
      end

      rule(:events) do
        events = value
        if events.length > 2
          key.failure("must contain at most registration and one terminal fact")
          next
        end
        next if events.empty?

        unless events.first.is_a?(Events::CommandRegisteredV1)
          key.failure("must start with CommandRegistered")
          next
        end

        command_ids = events.map(&:command_id).uniq
        key.failure("must describe one Command ID") unless command_ids.one?

        terminal = events.drop(1)
        next if terminal.empty?
        next if terminal.one? && (
          terminal.first.is_a?(Events::CommandSucceededV1) ||
          terminal.first.is_a?(Events::CommandRejectedV1) ||
          terminal.first.is_a?(Events::CommandRejectedV2)
        )

        key.failure("must contain at most one supported terminal fact")
      end
    end
  end
end
