# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskSubmittedV2 < Base
      contract type: "CoordinationTaskSubmitted", version: 2

      attribute :task_id, Types::TaskId
      attribute :tool_name, Types::CoordinationToolName
      attribute :command_id, Types::Identifier
      attribute :command_input, CommandInputDocuments::Type
      attribute :submitted_at, Types::Timestamp
      attribute :ttl_ms, Types::Nil
      attribute :poll_interval_ms, Types::Integer.constrained(eql: 500)
    end
  end
end
