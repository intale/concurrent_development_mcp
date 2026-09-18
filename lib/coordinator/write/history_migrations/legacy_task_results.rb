# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyTaskResults
      class NextActionV1 < Value
        attribute :tool, Types::String
        attribute :arguments, Types::Hash
      end

      class DomainErrorV1 < Value
        attribute :code, Types::Identifier
        attribute :message, Types::String
        attribute :details, Types::Hash
      end

      class SuccessV1 < Value
        Action = NextActionV1

        attribute :kind, Types::String.enum("success")
        attribute? :status, Types::String.enum("ok").optional
        attribute :summary, Types::String
        attribute :command_id, Types::Identifier
        attribute :receipt, Types::Identifier
        attribute :data, Types::Hash
        attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
        attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
      end

      class DomainRejectionV1 < Value
        Action = NextActionV1

        attribute :kind, Types::String.enum("domain_rejection")
        attribute :status, Types::String
        attribute :summary, Types::String
        attribute :command_id, Types::Identifier
        attribute :error, DomainErrorV1
        attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
      end

      class StructuredContentV1 < Value
        Action = NextActionV1

        attribute :status, Types::String
        attribute :summary, Types::String
        attribute :command_id, Types::Identifier
        attribute :receipt, Types::Identifier.optional
        attribute :context_token, Types::String.optional
        attribute :data, Types::Hash
        attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
        attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
      end

      Type = SuccessV1 | DomainRejectionV1
    end
  end
end
