# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class ResultV1 < Value
      Status = Types::String.enum(
        "ok",
        "command_id_reused",
        "denied",
        "conflict",
        "busy",
        "stale_context",
        "confirmation_required",
        "not_found",
        "limit_reached"
      )
      Data = Coordinator::Write::CommandReceiptData::Type |
             Coordinator::Write::Tasks::DomainErrorV1::Type

      attribute :command_id, Types::PublicCommandId
      attribute :tool_name, Types::CoordinationToolName
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :status, Status
      attribute :summary, Types::String
      attribute :receipt, Types::Identifier.optional
      attribute :data, Data
      attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
      attribute :next_actions,
                Types::Array.of(Coordinator::Write::NextAction).constrained(max_size: 100)
      attribute :emitted_events,
                Types::Array.of(Coordinator::Write::EventReference).constrained(max_size: 128)
      attribute :completed_at, Types::Timestamp

      def self.from_semantic(semantic_result:, tool_name:, canonical_input_digest:, emitted_events:, completed_at:)
        case semantic_result
        when Coordinator::Write::Tasks::SemanticResultV1::Success
          new(
            command_id: semantic_result.command_id,
            tool_name:,
            canonical_input_digest:,
            status: "ok",
            summary: semantic_result.summary,
            receipt: semantic_result.receipt,
            data: semantic_result.data,
            warnings: semantic_result.warnings,
            next_actions: semantic_result.next_actions,
            emitted_events:,
            completed_at:
          )
        when Coordinator::Write::Tasks::SemanticResultV1::DomainRejection
          new(
            command_id: semantic_result.command_id,
            tool_name:,
            canonical_input_digest:,
            status: semantic_result.status,
            summary: semantic_result.summary,
            receipt: nil,
            data: semantic_result.error,
            warnings: [],
            next_actions: semantic_result.next_actions,
            emitted_events:,
            completed_at:
          )
        end
      end

      def semantic_result
        if status == "ok"
          return Coordinator::Write::Tasks::SemanticResultV1::Success.new(
            kind: "success",
            summary:,
            command_id:,
            receipt: receipt || raise(InvalidProjectionSource, "Successful command result has no receipt"),
            data:,
            warnings:,
            next_actions:
          )
        end

        Coordinator::Write::Tasks::SemanticResultV1::DomainRejection.new(
          kind: "domain_rejection",
          status:,
          summary:,
          command_id:,
          error: Coordinator::Write::Tasks::DomainErrorV1::Type[data],
          next_actions:
        )
      end
    end
  end
end
