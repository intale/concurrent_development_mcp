# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class StructuredContentV1 < Value
      Data = DomainErrorV1::Type | CommandReceiptData::Type

      attribute :status, Types::String.enum(
        "ok",
        "invalid",
        "command_id_reused",
        "denied",
        "conflict",
        "busy",
        "stale_context",
        "confirmation_required",
        "not_found"
      )
      attribute :summary, Types::String
      attribute :command_id, Types::Identifier.optional
      attribute :receipt, Types::Identifier.optional
      attribute :context_token, Types::Sha256Digest.optional
      attribute :data, Data
      attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
      attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
    end
  end
end
