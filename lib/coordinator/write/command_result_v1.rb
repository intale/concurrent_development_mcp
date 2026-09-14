# frozen_string_literal: true

module Coordinator::Write
  class CommandResultV1 < Value
    attribute :command_id, Types::Identifier
    attribute :tool_name, Types::CoordinationToolName
    attribute :canonical_input_digest, Types::Sha256Digest
    attribute :status, Types::String.enum("ok")
    attribute :summary, Types::String
    attribute :receipt, Types::Identifier
    attribute :data, CommandReceiptData::Type
    attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
    attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
    attribute :emitted_events,
              Types::Array.of(EventReference).constrained(max_size: Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS)
    attribute :completed_at, Types::Timestamp
  end
end
