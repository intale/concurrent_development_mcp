# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskSubmittedV3 < Base
      contract type: "CoordinationTaskSubmitted", version: 3

      attribute :task_id, Types::TaskId
      attribute :command_id, Types::CommandId
      attribute :tool_name, Types::CoordinationToolName
      attribute :command_input, CommandInputDocuments::Type
      attribute :poll_interval_ms, Types::Integer.constrained(eql: 500)
      attribute :ttl_ms, Types::Nil
    end
  end
end
