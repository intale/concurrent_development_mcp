# frozen_string_literal: true

module Coordinator
  module Events
    class CommandCompletedV1 < Base
      contract type: "CommandCompleted", version: 1

      attribute :command_id, Types::Identifier
      attribute :tool_name, Types::String
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :status, Types::String.enum("ok")
      attribute :summary, Types::String
      attribute :receipt, Types::Identifier
      attribute :context_token, Types::Sha256Digest
      attribute :data, CommandReceiptData::Type
      attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
      attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
      attribute :emitted_events, Types::Array.of(EventReference).constrained(min_size: 1)
      attribute :projection_barriers, ProjectionBarriers
      attribute :completed_at, Types::Timestamp
    end
  end
end
