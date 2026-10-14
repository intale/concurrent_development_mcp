# frozen_string_literal: true

module Coordinator::Read::Projections
  class OperationBatches
    OUTCOMES = { "OperationBatchItemSucceeded" => "succeeded", "OperationBatchItemRejected" => "rejected",
      "OperationBatchItemFailed" => "failed", "OperationBatchItemRegistrationRejected" => "rejected" }.freeze

    def initialize(headers:, items:, outcomes:, item_sources: {}, arguments: Coordinator::Read::OperationBatchArguments.new)
      @headers, @items, @outcomes, @item_sources, @arguments = headers, items, outcomes, item_sources, arguments
    end

    def apply(event)
      data = event.data
      identity = { batch_id: data.fetch("batch_id") }
      case event.type
      when "OperationBatchCreated"
        attributes = identity.merge(page_size: event.metadata.fetch("page_size"), manifest_digest: event.metadata.fetch("manifest_digest"))
          .merge(Source.evidence(event, prefix: :created))
        @headers.insert(attributes.merge(status: "running", succeeded_count: 0, rejected_count: 0,
          cancellation_requested: false, created_at: event.created_at, updated_at: event.created_at))
        @headers.assign(attributes)
      when "OperationBatchTargetSelected" then @headers.assign(identity.merge(target_tool: data.fetch("target_tool")))
      when "OperationBatchManifestAccepted"
        @headers.assign(identity.merge(total: event.metadata.fetch("item_count"), encoded_byte_size: event.metadata.fetch("encoded_byte_size")))
      when "OperationBatchSucceededItemsNumberChanged" then @headers.assign(identity.merge(succeeded_count: data.fetch("items_number")))
      when "OperationBatchUnsuccessfulItemsNumberChanged" then @headers.assign(identity.merge(rejected_count: data.fetch("items_number")))
      when "OperationBatchOutcomeRecorded" then @headers.assign(identity.merge(status: data.fetch("outcome")))
      when "OperationBatchItemEnqueued" then enqueue(event)
      when "OperationBatchItemCommandAssigned"
        @items.assign(item_identity(data).merge(target_command_id: data.fetch("command_id")))
        @items.touch(item_identity(data), time: event.created_at)
      when "OperationBatchItemExecutionStarted" then @items.touch(item_identity(data), time: event.created_at)
      when "OperationBatchItemCompletionLinked"
        @outcomes.assign(item_identity(data).merge(completion_event: data.fetch("completion"), completion_link_event: Source.reference(event)))
        @outcomes.touch(item_identity(data), time: event.created_at)
      when "OperationBatchCancellationRequested"
        @headers.assign(identity.merge(cancellation_requested: true, status: "cancelling").merge(Source.evidence(event, prefix: :cancellation)))
      when "OperationBatchCompleted", "OperationBatchCancelled"
        @headers.assign(identity.merge(terminal_kind: event.type == "OperationBatchCompleted" ? "completed" : "cancelled")
          .merge(Source.evidence(event, prefix: :terminal)))
      else
        outcome(event) if OUTCOMES.key?(event.type)
      end
      @headers.touch(identity, time: event.created_at)
    end

    private

    def enqueue(event)
      data = event.data
      document = data.fetch("input")
      identity = item_identity(data)
      source = { command_id: document.fetch("command_id"), canonical_input_digest: event.metadata.fetch("canonical_input_digest") }
      @item_sources[identity.values_at(:batch_id, :item_index)] = source
      attributes = identity.merge(source).merge(target_tool: document.fetch("tool_name"),
        encoded_byte_size: event.metadata.fetch("encoded_byte_size"), arguments: @arguments.call(document))
      @items.insert(attributes.merge(target_command_id: nil, created_at: event.created_at, updated_at: event.created_at))
      @items.assign(attributes)
      @items.touch(identity, time: event.created_at)
      @outcomes.assign(identity.merge(source))
      @outcomes.touch(identity, time: event.created_at)
    end

    def outcome(event)
      data = event.data
      identity = item_identity(data)
      source = @item_sources.fetch(identity.values_at(:batch_id, :item_index), {})
      attributes = identity.merge(status: OUTCOMES.fetch(event.type), result: result(event), target_command_id: data["command_id"],
        finished_at_domain: event.created_at, finished_at_store: event.created_at)
        .merge(Source.evidence(event, prefix: :outcome).except(:outcome_at_domain, :outcome_at_store))
      @outcomes.insert(attributes.merge(source).merge(created_at: event.created_at, updated_at: event.created_at))
      @outcomes.assign(attributes)
      @outcomes.touch(identity, time: event.created_at)
    end

    def result(event)
      data = event.data
      case event.type
      when "OperationBatchItemFailed"
        { error: { code: "saga_execution_failed", message: data.fetch("reason"), details: data.except("batch_id", "index") } }
      when "OperationBatchItemRegistrationRejected" then { error: data.fetch("error") }
      when "OperationBatchItemRejected" then data.slice("code", "reason", "retryable")
      else {}
      end
    end

    def item_identity(data)
      { batch_id: data.fetch("batch_id"), item_index: data.fetch("index") }
    end
  end
end
