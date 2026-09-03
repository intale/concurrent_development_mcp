# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CommandRegisteredV1 < Base
      contract type: "CommandRegistered", version: 1

      attribute :command_id, Types::CommandId
      attribute :request_id, Types::RequestId
      attribute :tool_name, Types::CoordinationToolName
    end
  end
end
