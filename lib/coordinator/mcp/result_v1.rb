# frozen_string_literal: true

module Coordinator::Mcp
  class ResultV1 < Value
    class DomainError < Value
      attribute :code, Types::String
      attribute :message, Types::String
      attribute :details, Types::Hash
    end

    Data = DomainError |
           Coordinator::Write::CommandReceiptData::Type |
           Coordinator::Read::QueryResultV1::Data
    Action = Coordinator::Write::NextAction | Coordinator::Read::NextAction

    attribute :status, Types::String.enum(
      "ok",
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
    attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
  end
end
