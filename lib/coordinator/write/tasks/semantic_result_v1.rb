# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module SemanticResultV1
      class Success < Value
        attribute :kind, Types::String.enum("success")
        attribute :summary, Types::String
        attribute :command_id, Types::Identifier
        attribute :receipt, Types::Identifier
        attribute :data, CommandReceiptData::Type
        attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
        attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
      end

      class DomainRejection < Value
        attribute :kind, Types::String.enum("domain_rejection")
        attribute :status, Types::String.enum(
          "command_id_reused",
          "denied",
          "conflict",
          "busy",
          "stale_context",
          "confirmation_required",
          "not_found",
          "limit_reached"
        )
        attribute :summary, Types::String
        attribute :command_id, Types::Identifier
        attribute :error, DomainErrorV1::Type
        attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
      end

      Type = Success | DomainRejection
    end
  end
end
