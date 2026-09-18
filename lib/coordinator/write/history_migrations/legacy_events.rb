# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyEvents
      class DecisionSlotV1 < Value
        attribute :slot_id, Types::Identifier
        attribute :document, Decisions::DecisionSlotDocumentV1
        attribute :compound_marker, Coordinator::Shared::CompoundMarker
      end

      class DecisionActivatedV1 < Events::Base
        contract type: "DecisionActivated", version: 1

        Partition = Decisions::DecisionPartitionV1

        attribute :decision_id, Types::Identifier
        attribute :interpretation_id, Types::Identifier
        attribute :recorded_event, EventReference
        attribute :definition_digest, Types::Sha256Digest
        attribute :slot, DecisionSlotV1.optional
        attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
        attribute :rationale, Decisions::DecisionActivationRationaleV1
        attribute :activated_at, Types::Timestamp
      end

      class DecisionDefinitionCorrectedV1 < Events::Base
        contract type: "DecisionDefinitionCorrected", version: 1

        Partition = Decisions::DecisionPartitionV1

        attribute :decision_id, Types::Identifier
        attribute :interpretation_id, Types::Identifier
        attribute :source_message_id, Types::Identifier
        attribute :source_event, EventReference
        attribute :proposal_event, EventReference
        attribute :acceptance_event, EventReference
        attribute :previous_head, Decisions::DecisionHeadV1
        attribute :previous_definition_digest, Types::Sha256Digest
        attribute :definition, Decisions::DecisionDefinitionV1
        attribute :classifier, Interpretations::ClassifierAttributionV1
        attribute :scope_provenance, Interpretations::DecisionScopeProvenanceV1
        attribute :previous_slot, DecisionSlotV1.optional
        attribute :slot, DecisionSlotV1.optional
        attribute :previous_partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
        attribute :partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
        attribute :rationale, Decisions::DecisionCorrectionRationaleV1
        attribute :corrected_at, Types::Timestamp
      end

      class DecisionSlotOpenedV1 < Events::Base
        contract type: "DecisionSlotOpened", version: 1

        attribute :slot, DecisionSlotV1
        attribute :opened_by, Decisions::DecisionHeadV1
        attribute :opened_at, Types::Timestamp
      end

      class DevelopmentArtifactCapturedV2 < Events::Base
        contract type: "DevelopmentArtifactCaptured", version: 2

        attribute :artifact, LegacyDevelopmentArtifacts::ArtifactV2
        attribute :captured_at, Types::Timestamp
      end

      class DevelopmentArtifactObservedV1 < Events::Base
        contract type: "DevelopmentArtifactObserved", version: 1

        attribute :observation, LegacyDevelopmentArtifacts::ArtifactObservationV1
        attribute :recorded_at, Types::Timestamp
      end

      class DevelopmentArtifactClassificationCorrectedV1 < Events::Base
        contract type: "DevelopmentArtifactClassificationCorrected", version: 1

        attribute :observation_id, LegacyDevelopmentArtifactTypes::ObservationId
        attribute :artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :reason, Types::String.constrained(min_size: 1, max_size: 1_000)
        attribute :corrected_at, Types::Timestamp
      end

      class DevelopmentArtifactRelationDeclaredV1 < Events::Base
        contract type: "DevelopmentArtifactRelationDeclared", version: 1

        attribute :artifact_relation, LegacyDevelopmentArtifacts::RelationV1
        attribute :declared_at, Types::Timestamp
      end

      class DevelopmentArtifactRelationSupersededV1 < Events::Base
        contract type: "DevelopmentArtifactRelationSuperseded", version: 1

        attribute :source_artifact_id, LegacyDevelopmentArtifactTypes::ArtifactId
        attribute :superseded_relation_id, LegacyDevelopmentArtifactTypes::RelationId
        attribute :replacement_relation_id, LegacyDevelopmentArtifactTypes::RelationId
        attribute :reason, Types::DevelopmentArtifactRelationSupersessionReason
        attribute :superseded_at, Types::Timestamp
      end

      class CommandCompletedV1 < Events::Base
        contract type: "CommandCompleted", version: 1
        Action = LegacyTaskResults::NextActionV1 | NextAction

        attribute :command_id, Types::Identifier
        attribute :tool_name, Types::String
        attribute :canonical_input_digest, Types::Sha256Digest
        attribute :status, Types::String.enum("ok")
        attribute :summary, Types::String
        attribute :receipt, Types::Identifier
        attribute :data, Types::Hash | CommandReceiptData::Type
        attribute :warnings, Types::Array.of(Types::String).constrained(max_size: 100)
        attribute :next_actions, Types::Array.of(Action).constrained(max_size: 100)
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
        attribute :result, LegacyTaskResults::Type | Tasks::SemanticResultV1::Type
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
        attribute :command_input, Types::Hash | CommandInputDocuments::Type
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
        Item = LegacyCommandInputDocuments::OperationBatchItemV1 | OperationBatches::ItemV1

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
        attribute :result, LegacyTaskResults::StructuredContentV1 | Tasks::StructuredContentV1
        attribute :finished_at, Types::Timestamp
      end

      class OperationBatchItemSucceededV1 < Events::Base
        contract type: "OperationBatchItemSucceeded", version: 1

        attribute :batch_id, Types::OperationBatchId
        attribute :index, Types::OperationBatchItemIndex
        attribute :command_id, Types::Identifier
        attribute :canonical_input_digest, Types::Sha256Digest
        attribute :target_completion, EventReference
        attribute :result, LegacyTaskResults::StructuredContentV1 | Tasks::StructuredContentV1
        attribute :finished_at, Types::Timestamp
      end
    end
  end
end
