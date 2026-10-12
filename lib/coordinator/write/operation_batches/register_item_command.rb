# frozen_string_literal: true

module Coordinator::Write::OperationBatches
  class RegisterItemCommand
    def call(item:)
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id: item.command_id, request_id: item.request_id, tool_name: item.tool_name
      )
    end
  end
end
