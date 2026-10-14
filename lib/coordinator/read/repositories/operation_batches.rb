# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class OperationBatches
      def initialize(
        command_receipts: CommandReceipts.new
      )
        @command_receipts = command_receipts
      end

      def fetch(query)
        record = Coordinator::Read::OperationBatch.find_by(batch_id: query.batch_id)
        return unless record&.total

        rows = item_relation(record, query).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        selected = rows.first(query.limit)
        outcomes = outcomes_by_index(record, selected)
        receipts = receipts_by_command_id(outcomes.values)
        unprocessed = record.total - record.succeeded_count - record.rejected_count
        items = selected.map do |item|
          outcome = outcomes[item.item_index]
          build_item(
            item,
            outcome,
            receipt: outcome && receipts[outcome.target_command_id],
            terminal_kind: record.terminal_kind
          )
        end

        OperationBatchViewV1.new(
          batch_id: record.batch_id,
          target_tool: record.target_tool,
          status: record.status,
          total: record.total,
          succeeded: record.succeeded_count,
          rejected: record.rejected_count,
          pending: record.terminal_kind ? 0 : unprocessed,
          not_run: record.terminal_kind == "cancelled" ? unprocessed : 0,
          manifest_digest: record.manifest_digest,
          encoded_byte_size: record.encoded_byte_size,
          items:,
          next_after_index: has_more ? items.last.index : nil,
          has_more:,
          created: source_evidence(record, "created"),
          cancellation: record.cancellation_event && source_evidence(record, "cancellation"),
          terminal: record.terminal_event && source_evidence(record, "terminal")
        )
      end

      private

      def item_relation(record, query)
        relation = Coordinator::Read::OperationBatchItem.where(batch_id: record.batch_id)
        relation = relation.where("item_index > ?", query.after_index) if query.after_index
        relation.order(:item_index)
      end

      def outcomes_by_index(record, items)
        indexes = items.map(&:item_index)
        Coordinator::Read::OperationBatchOutcome.where(
          batch_id: record.batch_id,
          item_index: indexes
        ).index_by(&:item_index)
      end

      def receipts_by_command_id(outcomes)
        command_ids = outcomes.map(&:target_command_id).compact
        @command_receipts.fetch_index(command_ids)
      end

      def build_item(item, outcome, receipt:, terminal_kind:)
        OperationBatchItemViewV1.new(
          index: item.item_index,
          target_tool: item.target_tool,
          command_id: item.command_id,
          canonical_input_digest: item.canonical_input_digest,
          arguments: symbolize(item.arguments),
          status: item_status(outcome, terminal_kind:),
          result: receipt ? structured_content(receipt) : registration_rejection(item, outcome),
          finished_at: outcome&.finished_at_domain&.utc&.iso8601(6),
          source: outcome && outcome_source_evidence(outcome)
        )
      end

      def structured_content(receipt)
        Coordinator::Write::Tasks::StructuredContentV1.new(
          status: receipt.status,
          summary: receipt.summary,
          command_id: receipt.command_id,
          receipt: receipt.receipt,
          context_token: nil,
          data: receipt.data,
          warnings: receipt.warnings,
          next_actions: receipt.next_actions,
          completion: receipt.semantic_result.completion
        )
      end

      def registration_rejection(item, outcome)
        return unless outcome && outcome.result.key?("error")

        error = Coordinator::Write::Tasks::DomainErrorV1::Type[symbolize(outcome.result.fetch("error"))]
        Coordinator::Write::Tasks::StructuredContentV1.new(
          status: error.code == "saga_execution_failed" ? "failed" : "command_id_reused", summary: error.message, command_id: item.command_id,
          receipt: nil, context_token: nil, data: error, warnings: [], next_actions: [],
          completion: Coordinator::Write::Tasks::CompletionGuaranteeBuilder.new.rejection(tool_name: item.target_tool, error:)
        )
      end

      def item_status(outcome, terminal_kind:)
        return outcome.status if outcome

        terminal_kind == "cancelled" ? "not_run" : "pending"
      end

      def source_evidence(record, prefix)
        OperationBatchSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.public_send("#{prefix}_event"))),
          actor: AttributedActorV1.new(symbolize(record.public_send("#{prefix}_actor"))),
          markers: record.public_send("#{prefix}_markers"),
          metadata: record.public_send("#{prefix}_metadata"),
          global_position: record.public_send("#{prefix}_global_position"),
          occurred_at: record.public_send("#{prefix}_at_domain").utc.iso8601(6),
          persisted_at: record.public_send("#{prefix}_at_store").utc.iso8601(6),
          causation_id: record.public_send("#{prefix}_causation_id"),
          correlation_id: record.public_send("#{prefix}_correlation_id")
        )
      end

      def outcome_source_evidence(record)
        OperationBatchSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.outcome_event)),
          actor: AttributedActorV1.new(symbolize(record.outcome_actor)),
          markers: record.outcome_markers,
          metadata: record.outcome_metadata,
          global_position: record.outcome_global_position,
          occurred_at: record.finished_at_domain.utc.iso8601(6),
          persisted_at: record.finished_at_store.utc.iso8601(6),
          causation_id: record.outcome_causation_id,
          correlation_id: record.outcome_correlation_id
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
