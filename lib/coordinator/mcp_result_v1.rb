# frozen_string_literal: true

module Coordinator
  class McpResultV1 < Value
    class EmptyData < Value
    end

    class DomainError < Value
      attribute :code, Types::String
      attribute :message, Types::String
      attribute :details, Types::Hash
    end

    class OperationData < Value
      attribute :result, CommandReceiptData::Type
      attribute :emitted_events, Types::Array.of(EventReference).constrained(min_size: 1)
      attribute :projection_barriers, ProjectionBarriers
      attribute :projection_progress, Types::Array.of(ProjectionProgressV1).constrained(min_size: 1, max_size: 10)
    end

    class PendingContextData < Value
      attribute :scope, ContextTokenDocument::Scope
      attribute :projection_progress, Types::Array.of(ProjectionProgressV1).constrained(min_size: 1, max_size: 10)
    end

    class ContextData < Value
      attribute :scope, ContextTokenDocument::Scope
      attribute :context, Projections::CoordContextStateV1
      attribute :blockers, Types::Array.of(ContextBlockerV1).constrained(max_size: 500)
      attribute :source_positions, Types::Array.of(ProjectionBarrier).constrained(min_size: 1, max_size: 256)
      attribute :freshness, Types::String.enum("observed", "current_for_requested_command")
      attribute :last_processed_at, Types::Timestamp
    end

    class NotModifiedData < Value
      attribute :scope, ContextTokenDocument::Scope
      attribute :freshness, Types::String.enum("observed", "current_for_requested_command")
      attribute :last_processed_at, Types::Timestamp
    end

    Data = EmptyData |
           DomainError |
           OperationData |
           PendingContextData |
           ContextData |
           NotModifiedData |
           CommandReceiptData::Type

    attribute :status, Types::String.enum(
      "ok",
      "pending_projection",
      "not_found",
      "invalid",
      "not_modified",
      "command_id_reused",
      "denied",
      "conflict",
      "busy"
    )
    attribute :summary, Types::String
    attribute :command_id, Types::Identifier.optional
    attribute :receipt, Types::Identifier.optional
    attribute :context_token, Types::Sha256Digest.optional
    attribute :data, Data
    attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
    attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
    attribute :projection_status, Types::String.enum(
      "pending",
      "observed",
      "current_for_requested_command"
    ).optional
  end
end
