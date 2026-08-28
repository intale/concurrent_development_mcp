# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class OperationBatches
      def initialize(arguments_builder: OperationBatchArguments.new)
        @arguments_builder = arguments_builder
      end

      def fetch(query)
        record = Coordinator::Read::OperationBatch.find_by(batch_id: query.batch_id)
        return unless record&.total

        rows = item_relation(record, query).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        selected = rows.first(query.limit)
        outcomes = outcomes_by_index(record, selected)
        unprocessed = record.total - record.succeeded_count - record.rejected_count
        items = selected.map { build_item(_1, outcomes[_1.item_index], terminal_kind: record.terminal_kind) }

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

      def store(event:, payload:)
        record = Coordinator::Read::OperationBatch.lock.find_or_create_by!(batch_id: payload.batch_id)
        case payload
        when Coordinator::Write::Events::OperationBatchCreatedV1
          store_creation(record, event, payload)
        when Coordinator::Write::Events::OperationBatchItemSucceededV1
          store_outcome(record, event, payload, status: "succeeded")
        when Coordinator::Write::Events::OperationBatchItemRejectedV1
          store_outcome(record, event, payload, status: "rejected")
        when Coordinator::Write::Events::OperationBatchCancellationRequestedV1
          store_cancellation(record, event, payload)
        when Coordinator::Write::Events::OperationBatchCompletedV1
          store_terminal(record, event, payload, kind: "completed")
        when Coordinator::Write::Events::OperationBatchCancelledV1
          store_terminal(record, event, payload, kind: "cancelled")
        end
        refresh_summary(record)
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

      def store_creation(record, event, payload)
        if record.created_event && record.manifest_digest != payload.manifest_digest
          raise ProjectionStateError, "Operation Batch creation changed for one stream"
        end

        record.update!(
          target_tool: payload.target_tool,
          total: payload.total,
          page_size: payload.page_size,
          manifest_digest: payload.manifest_digest,
          encoded_byte_size: payload.encoded_byte_size,
          created_event: event_reference(event).to_h,
          created_actor: actor(event).to_h,
          created_markers: event.markers,
          created_metadata: event.metadata,
          created_causation_id: event.causation_id,
          created_correlation_id: event.correlation_id,
          created_global_position: event.global_position,
          created_at_domain: payload.created_at,
          created_at_store: event.created_at
        )
        payload.items.each { store_item(record, _1) }
      end

      def store_item(batch, item)
        record = Coordinator::Read::OperationBatchItem.find_or_initialize_by(
          batch_id: batch.batch_id,
          item_index: item.index
        )
        attributes = {
          target_tool: item.command_input.tool_name,
          command_id: item.command_input.command_id,
          canonical_input_digest: item.canonical_input_digest,
          arguments: @arguments_builder.call(item.command_input)
        }
        if record.persisted?
          matches = record.target_tool == attributes.fetch(:target_tool) &&
                    record.command_id == attributes.fetch(:command_id) &&
                    record.canonical_input_digest == attributes.fetch(:canonical_input_digest) &&
                    record.arguments == attributes.fetch(:arguments).deep_stringify_keys
          unless matches
            raise ProjectionStateError, "Operation Batch manifest item changed for one stream"
          end
          return
        end

        record.assign_attributes(attributes)
        record.save!
      end

      def store_outcome(record, event, payload, status:)
        outcome = Coordinator::Read::OperationBatchOutcome.find_or_initialize_by(
          batch_id: record.batch_id,
          item_index: payload.index
        )
        if outcome.persisted?
          verify_outcome!(outcome, payload, status:)
          return
        end

        outcome.assign_attributes(
          command_id: payload.command_id,
          canonical_input_digest: payload.canonical_input_digest,
          status:,
          result: payload.result.to_h,
          outcome_event: event_reference(event).to_h,
          outcome_actor: actor(event).to_h,
          outcome_markers: event.markers,
          outcome_metadata: event.metadata,
          outcome_causation_id: event.causation_id,
          outcome_correlation_id: event.correlation_id,
          outcome_global_position: event.global_position,
          finished_at_domain: payload.finished_at,
          finished_at_store: event.created_at
        )
        outcome.save!
      end

      def verify_outcome!(outcome, payload, status:)
        matches = outcome.command_id == payload.command_id &&
                  outcome.canonical_input_digest == payload.canonical_input_digest &&
                  outcome.status == status &&
                  outcome.result == payload.result.to_h.deep_stringify_keys
        return if matches

        raise ProjectionStateError, "Operation Batch item has conflicting outcomes"
      end

      def store_cancellation(record, event, payload)
        record.update!(
          cancellation_requested: true,
          cancellation_event: event_reference(event).to_h,
          cancellation_actor: actor(event).to_h,
          cancellation_markers: event.markers,
          cancellation_metadata: event.metadata,
          cancellation_causation_id: event.causation_id,
          cancellation_correlation_id: event.correlation_id,
          cancellation_global_position: event.global_position,
          cancellation_at_domain: payload.requested_at,
          cancellation_at_store: event.created_at
        )
      end

      def store_terminal(record, event, payload, kind:)
        if record.terminal_kind && record.terminal_kind != kind
          raise ProjectionStateError, "Operation Batch has conflicting terminal outcomes"
        end

        record.update!(
          terminal_kind: kind,
          terminal_event: event_reference(event).to_h,
          terminal_actor: actor(event).to_h,
          terminal_markers: event.markers,
          terminal_metadata: event.metadata,
          terminal_causation_id: event.causation_id,
          terminal_correlation_id: event.correlation_id,
          terminal_global_position: event.global_position,
          terminal_at_domain: kind == "completed" ? payload.completed_at : payload.cancelled_at,
          terminal_at_store: event.created_at
        )
      end

      def refresh_summary(record)
        statuses = Coordinator::Read::OperationBatchOutcome.where(batch_id: record.batch_id).group(:status).count
        succeeded = statuses.fetch("succeeded", 0)
        rejected = statuses.fetch("rejected", 0)
        status = case record.terminal_kind
        when "cancelled" then "cancelled"
        when "completed" then rejected.positive? ? "completed_with_errors" : "completed"
        else record.cancellation_requested ? "cancelling" : "running"
        end
        record.update!(succeeded_count: succeeded, rejected_count: rejected, status:)
      end

      def build_item(item, outcome, terminal_kind:)
        OperationBatchItemViewV1.new(
          index: item.item_index,
          target_tool: item.target_tool,
          command_id: item.command_id,
          canonical_input_digest: item.canonical_input_digest,
          arguments: symbolize(item.arguments),
          status: item_status(outcome, terminal_kind:),
          result: outcome && Coordinator::Write::Tasks::StructuredContentV1.new(symbolize(outcome.result)),
          finished_at: outcome&.finished_at_domain&.utc&.iso8601(6),
          source: outcome && outcome_source_evidence(outcome)
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

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
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
