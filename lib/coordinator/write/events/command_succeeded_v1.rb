# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CommandSucceededV1 < Base
      contract type: "CommandSucceeded", version: 1

      attribute :command_id, Types::CommandId
    end
  end
end
