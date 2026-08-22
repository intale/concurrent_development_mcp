# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CoordinationTaskSubmittedV1 < Base
      contract type: "CoordinationTaskSubmitted", version: 1

      attribute :task_id, Types::TaskId
      attribute :tool_name, Types::String.enum(
        "change_set_create",
        "work_item_create",
        "work_item_dependency_declare",
        "change_set_activate",
        "work_item_acquire"
      )
      attribute :command_id, Types::Identifier
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :command_input, CommandInputDocuments::Type
      attribute :submitted_at, Types::Timestamp
      attribute :ttl_ms, Types::Nil
      attribute :poll_interval_ms, Types::Integer.constrained(eql: 500)
    end
  end
end
