# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyEvents
      class CommandCompletedV1 < Events::Base
        contract type: "CommandCompleted", version: 1

        attribute :command_id, Types::Identifier
        attribute :tool_name, Types::String
        attribute :canonical_input_digest, Types::Sha256Digest
        attribute :status, Types::String.enum("ok")
        attribute :summary, Types::String
        attribute :receipt, Types::Identifier
        attribute :data, CommandReceiptData::Type
        attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
        attribute :next_actions, Types::Array.of(NextAction).constrained(max_size: 100)
        attribute :emitted_events, Types::Array.of(EventReference)
        attribute :completed_at, Types::Timestamp
      end

      class CoordinationTaskCancellationRequestedV1 < Events::Base
        contract type: "CoordinationTaskCancellationRequested", version: 1

        attribute :task_id, Types::TaskId
        attribute :requested_at, Types::Timestamp
      end

      class CoordinationTaskCancelledV1 < Events::Base
        contract type: "CoordinationTaskCancelled", version: 1

        attribute :task_id, Types::TaskId
        attribute :reason, Types::String.enum("cancelled_before_execution")
        attribute :cancelled_at, Types::Timestamp
      end

      class CoordinationTaskCompletedV2 < Events::Base
        contract type: "CoordinationTaskCompleted", version: 2

        attribute :task_id, Types::TaskId
        attribute :result, Tasks::SemanticResultV1::Type
        attribute :completed_at, Types::Timestamp
      end

      class CoordinationTaskExecutionStartedV1 < Events::Base
        contract type: "CoordinationTaskExecutionStarted", version: 1

        attribute :task_id, Types::TaskId
        attribute :started_at, Types::Timestamp
      end

      class CoordinationTaskFailedV1 < Events::Base
        contract type: "CoordinationTaskFailed", version: 1

        attribute :task_id, Types::TaskId
        attribute :error, Tasks::JsonRpcErrorV1
        attribute :failed_at, Types::Timestamp
      end

      class CoordinationTaskSubmittedV2 < Events::Base
        contract type: "CoordinationTaskSubmitted", version: 2

        attribute :task_id, Types::TaskId
        attribute :tool_name, Types::CoordinationToolName
        attribute :command_id, Types::Identifier
        attribute :command_input, CommandInputDocuments::Type
        attribute :submitted_at, Types::Timestamp
        attribute :ttl_ms, Types::Nil
        attribute :poll_interval_ms, Types::Integer.constrained(eql: 500)
      end

      class OperationBatchCancellationRequestedV1 < Events::Base
        contract type: "OperationBatchCancellationRequested", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :requester, OperationBatches::ActorV1
        attribute :requested_at, Types::Timestamp
      end

      class OperationBatchCancelledV1 < Events::Base
        contract type: "OperationBatchCancelled", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :succeeded, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
        attribute :rejected, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
        attribute :not_run, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
        attribute :cancellation_event, EventReference
        attribute :cancelled_at, Types::Timestamp
      end

      class OperationBatchCompletedV1 < Events::Base
        contract type: "OperationBatchCompleted", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :succeeded, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
        attribute :rejected, Types::Integer.constrained(gteq: 0, lteq: Types::OPERATION_BATCH_MAXIMUM_ITEMS)
        attribute :outcome_manifest_digest, Types::Sha256Digest
        attribute :completed_at, Types::Timestamp
      end

      class OperationBatchContinuationRequestedV1 < Events::Base
        contract type: "OperationBatchContinuationRequested", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :page_start, Types::OperationBatchItemIndex
        attribute :page_end, Types::OperationBatchItemIndex
        attribute :source_event, EventReference
        attribute :requested_at, Types::Timestamp
      end

      class OperationBatchCreatedV1 < Events::Base
        contract type: "OperationBatchCreated", version: 1
        Item = OperationBatches::ItemV1

        attribute :batch_id, Types::OperationBatchId
        attribute :target_tool, Types::OperationBatchTargetTool
        attribute :total, Types::OperationBatchTotal
        attribute :page_size, Types::OperationBatchPageSize
        attribute :items, Types::Array.of(Item).constrained(
          min_size: 1,
          max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
        )
        attribute :manifest_digest, Types::Sha256Digest
        attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
        attribute :requester, OperationBatches::ActorV1
        attribute :created_at, Types::Timestamp
      end

      class OperationBatchItemRejectedV1 < Events::Base
        contract type: "OperationBatchItemRejected", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :index, Types::OperationBatchItemIndex
        attribute :command_id, Types::Identifier
        attribute :canonical_input_digest, Types::Sha256Digest
        attribute :result, Tasks::StructuredContentV1
        attribute :finished_at, Types::Timestamp
      end

      class OperationBatchItemSucceededV1 < Events::Base
        contract type: "OperationBatchItemSucceeded", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :index, Types::OperationBatchItemIndex
        attribute :command_id, Types::Identifier
        attribute :canonical_input_digest, Types::Sha256Digest
        attribute :target_completion, EventReference
        attribute :result, Tasks::StructuredContentV1
        attribute :finished_at, Types::Timestamp
      end
    end
  end
end
