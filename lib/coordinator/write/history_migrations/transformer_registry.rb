# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TransformerRegistry
      include Dry::Monads[:result]

      def initialize(
        schema_registry: SourceEventSchemaRegistry.new,
        repository_registered_v1:,
        post_remodel_repository:,
        guidance_message_v1:,
        change_set_v1:,
        work_item_v1:,
        attempt_v1:,
        candidate_submission_v1:,
        candidate_evidence_v1:,
        candidate_head_v1:,
        candidate_impact_v1:,
        candidate_impact_scan_v1:,
        interpretation_lifecycle_v1:,
        decision_lifecycle_v1:,
        decision_relation_v1:,
        agent_choice_v1:,
        agent_choice_impact_v1:,
        agent_choice_impact_scan_v1:,
        coordination_task_submitted_v2:,
        coordination_task_lifecycle:,
        command_completed_v1:,
        operation_batch_v1:,
        resource_v1:,
        work_intention_v1:,
        development_artifact_v1:,
        development_artifact_relation_v1:,
        skill_revision_published_v2:,
        merge_snapshot_v1:,
        merge_snapshot_verification_v1:,
        merge_authorization_v1:,
        merge_observation_v1:,
        release_set_v1:,
        verification_obligation_v1:,
        verification_obligation_validity_scan_v1:,
        post_remodel_work_item:,
        post_remodel_attempt:,
        post_remodel_candidate:,
        post_remodel_command_task:,
        post_remodel_development_memory:,
        post_remodel_work_intention:
      )
        @schema_registry = schema_registry
        @definitions = {
          [ "RepositoryRegistered", 1 ] => repository_registered_v1,
          [ "RepositoryRegistered", 2 ] => post_remodel_repository,
          [ "RepositoryDisplayNameChanged", 1 ] => post_remodel_repository,
          [ "RepositoryPathAdded", 1 ] => post_remodel_repository,
          [ "RepositoryPathRemoved", 1 ] => post_remodel_repository,
          [ "RepositoryRemoteAdded", 1 ] => post_remodel_repository,
          [ "RepositoryRemoteRemoved", 1 ] => post_remodel_repository,
          [ "UserUtteranceRecorded", 1 ] => guidance_message_v1,
          [ "UserUtteranceForwardedByAgent", 1 ] => guidance_message_v1,
          [ "ChangeSetCreated", 1 ] => change_set_v1,
          [ "ChangeSetAcceptanceCriteriaDefined", 1 ] => change_set_v1,
          [ "ChangeSetActivated", 1 ] => change_set_v1,
          [ "ChangeSetCompleted", 1 ] => change_set_v1,
          [ "WorkItemCreated", 1 ] => work_item_v1,
          [ "WorkItemAddedToChangeSet", 1 ] => work_item_v1,
          [ "WorkItemDependencyDeclared", 1 ] => work_item_v1,
          [ "WorkItemDependencySatisfied", 1 ] => work_item_v1,
          [ "WorkItemMadeReady", 1 ] => work_item_v1,
          [ "WorkItemAcquired", 1 ] => work_item_v1,
          [ "WorkItemRequeued", 1 ] => work_item_v1,
          [ "WorkItemCandidateSelected", 1 ] => work_item_v1,
          [ "WorkItemCompleted", 1 ] => work_item_v1,
          [ "AttemptAuthorized", 1 ] => attempt_v1,
          [ "AttemptStarted", 1 ] => attempt_v1,
          [ "AttemptCompleted", 1 ] => attempt_v1,
          [ "AttemptAbandoned", 2 ] => attempt_v1,
          [ "CandidateSubmitted", 2 ] => candidate_submission_v1,
          [ "CandidateChangeManifestCaptured", 1 ] => candidate_evidence_v1,
          [ "CandidateBuildContextCaptured", 1 ] => candidate_evidence_v1,
          [ "CandidateHeadRegistered", 1 ] => candidate_head_v1,
          [ "CandidateAttachedToAttempt", 1 ] => candidate_submission_v1,
          [ "CandidateImpactSurfaceDerived", 1 ] => candidate_impact_v1,
          [ "CandidateImpactSurfaceRegistered", 1 ] => candidate_impact_v1,
          [ "CandidateImpactPairScanStarted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanProgressed", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanSkipped", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanCompleted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepStarted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepProgressed", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepSkipped", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepCompleted", 1 ] => candidate_impact_scan_v1,
          [ "DecisionInterpretationProposed", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionClarificationRequired", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionInterpretationAccepted", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionInterpretationRejected", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionRecorded", 1 ] => decision_lifecycle_v1,
          [ "DecisionActivated", 1 ] => decision_lifecycle_v1,
          [ "DecisionDefinitionCorrected", 1 ] => decision_lifecycle_v1,
          [ "DecisionSlotOpened", 1 ] => decision_relation_v1,
          [ "DecisionSlotHeadChanged", 1 ] => decision_relation_v1,
          [ "DecisionPartitionAdvanced", 1 ] => decision_relation_v1,
          [ "AgentChoiceRecorded", 1 ] => agent_choice_v1,
          [ "AgentChoiceAccepted", 1 ] => agent_choice_v1,
          [ "AgentChoiceImpactAssessed", 1 ] => agent_choice_impact_v1,
          [ "AgentChoiceInvalidatedByDecision", 1 ] => agent_choice_impact_v1,
          [ "AgentChoiceImpactScanStarted", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanSkipped", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanProgressed", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanCompleted", 1 ] => agent_choice_impact_scan_v1,
          [ "CoordinationTaskSubmitted", 2 ] => coordination_task_submitted_v2,
          [ "CoordinationTaskExecutionStarted", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancellationRequested", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancelled", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCompleted", 2 ] => coordination_task_lifecycle,
          [ "CoordinationTaskFailed", 1 ] => coordination_task_lifecycle,
          [ "CommandCompleted", 1 ] => command_completed_v1,
          [ "OperationBatchCreated", 1 ] => operation_batch_v1,
          [ "OperationBatchItemSucceeded", 1 ] => operation_batch_v1,
          [ "OperationBatchItemRejected", 1 ] => operation_batch_v1,
          [ "OperationBatchContinuationRequested", 1 ] => operation_batch_v1,
          [ "OperationBatchCancellationRequested", 1 ] => operation_batch_v1,
          [ "OperationBatchCancelled", 1 ] => operation_batch_v1,
          [ "OperationBatchCompleted", 1 ] => operation_batch_v1,
          [ "ResourceRegistered", 1 ] => resource_v1,
          [ "ResourceBound", 1 ] => resource_v1,
          [ "ResourceUnbound", 1 ] => resource_v1,
          [ "ResourceLeaseAcquired", 2 ] => work_intention_v1,
          [ "ResourceLeaseRenewed", 2 ] => work_intention_v1,
          [ "ResourceLeaseReleased", 2 ] => work_intention_v1,
          [ "ResourceLeaseExpired", 2 ] => work_intention_v1,
          [ "ResourceBoundaryEpochRolled", 2 ] => work_intention_v1,
          [ "WriteSetReserved", 2 ] => work_intention_v1,
          [ "WriteSetExpanded", 2 ] => work_intention_v1,
          [ "WriteSetRenewed", 2 ] => work_intention_v1,
          [ "WriteSetReleased", 2 ] => work_intention_v1,
          [ "DevelopmentArtifactCaptured", 2 ] => development_artifact_v1,
          [ "DevelopmentArtifactObserved", 1 ] => development_artifact_v1,
          [ "DevelopmentArtifactClassificationCorrected", 1 ] => development_artifact_v1,
          [ "DevelopmentArtifactRelationDeclared", 1 ] => development_artifact_relation_v1,
          [ "DevelopmentArtifactRelationSuperseded", 1 ] => development_artifact_relation_v1,
          [ "SkillRevisionPublished", 2 ] => skill_revision_published_v2,
          [ "MergeSnapshotRegistered", 1 ] => merge_snapshot_v1,
          [ "MergeSnapshotCommitRegistered", 1 ] => merge_snapshot_v1,
          [ "MergeSnapshotVerificationSubmitted", 1 ] => merge_snapshot_verification_v1,
          [ "MergeSnapshotVerified", 1 ] => merge_snapshot_verification_v1,
          [ "MergeAuthorizationGranted", 1 ] => merge_authorization_v1,
          [ "MergeAuthorizationDenied", 1 ] => merge_authorization_v1,
          [ "MergeObserved", 1 ] => merge_observation_v1,
          [ "ReleaseSetPrepared", 1 ] => release_set_v1,
          [ "RepositoryIntegrationRecorded", 1 ] => release_set_v1,
          [ "ReleaseSetVerificationRecorded", 1 ] => release_set_v1,
          [ "ReleaseSetActivated", 1 ] => release_set_v1,
          [ "ReleaseSetCompensationRequested", 1 ] => release_set_v1,
          [ "ReleaseSetCompleted", 1 ] => release_set_v1,
          [ "VerificationObligationCreated", 1 ] => verification_obligation_v1,
          [ "VerificationObligationClaimed", 1 ] => verification_obligation_v1,
          [ "VerificationEvidenceSubmitted", 1 ] => verification_obligation_v1,
          [ "VerificationObligationSatisfied", 1 ] => verification_obligation_v1,
          [ "VerificationObligationFailed", 1 ] => verification_obligation_v1,
          [ "VerificationObligationInvalidated", 1 ] => verification_obligation_v1,
          [ "VerificationObligationWaived", 1 ] => verification_obligation_v1,
          [ "VerificationObligationValidityScanStarted", 1 ] =>
            verification_obligation_validity_scan_v1,
          [ "VerificationObligationValidityScanProgressed", 1 ] =>
            verification_obligation_validity_scan_v1,
          [ "VerificationObligationValidityScanCompleted", 1 ] =>
            verification_obligation_validity_scan_v1,
          [ "WorkItemAcquired", 2 ] => post_remodel_work_item,
          [ "WorkItemCandidateSelected", 2 ] => post_remodel_work_item,
          [ "WorkItemCompleted", 2 ] => post_remodel_work_item,
          [ "WorkItemDependencySatisfied", 2 ] => post_remodel_work_item,
          [ "WorkItemMadeReady", 2 ] => post_remodel_work_item,
          [ "WorkItemRequeued", 2 ] => post_remodel_work_item,
          [ "AttemptAbandoned", 3 ] => post_remodel_attempt,
          [ "AttemptAssignedToAgent", 1 ] => post_remodel_attempt,
          [ "AttemptAssignedToWorkItem", 1 ] => post_remodel_attempt,
          [ "AttemptAuthorized", 2 ] => post_remodel_attempt,
          [ "AttemptBaseSnapshotRecorded", 1 ] => post_remodel_attempt,
          [ "AttemptCompleted", 2 ] => post_remodel_attempt,
          [ "AttemptStarted", 2 ] => post_remodel_attempt,
          [ "CandidateAssignedToAttempt", 1 ] => post_remodel_candidate,
          [ "CandidateAssignedToRepository", 1 ] => post_remodel_candidate,
          [ "CandidateChangeManifestCaptured", 2 ] => post_remodel_candidate,
          [ "CandidateCheckpointKindSelected", 1 ] => post_remodel_candidate,
          [ "CandidateCommitRangeDeclared", 1 ] => post_remodel_candidate,
          [ "CandidateCreated", 1 ] => post_remodel_candidate,
          [ "CandidateHeadRegistered", 2 ] => post_remodel_candidate,
          [ "CandidateSubmitted", 3 ] => post_remodel_candidate,
          [ "CandidateTargetBranchSelected", 1 ] => post_remodel_candidate,
          [ "CandidateWorkIntentionSetAssigned", 1 ] => post_remodel_candidate,
          [ "CommandRegistered", 1 ] => post_remodel_command_task,
          [ "CommandRejected", 1 ] => post_remodel_command_task,
          [ "CommandRejected", 2 ] => post_remodel_command_task,
          [ "CommandSucceeded", 1 ] => post_remodel_command_task,
          [ "CoordinationTaskCompleted", 3 ] => post_remodel_command_task,
          [ "CoordinationTaskExecutionStarted", 2 ] => post_remodel_command_task,
          [ "CoordinationTaskSubmitted", 3 ] => post_remodel_command_task,
          [ "ProcessStepPlanned", 1 ] => post_remodel_command_task,
          [ "DevelopmentArtifactContentChanged", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactCreated", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactKindChanged", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactLabelAdded", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactLabelRemoved", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactObservationFactLinked", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactObservationRecorded", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactRelationDeclared", 2 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactScopeChanged", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactSourceChanged", 1 ] => post_remodel_development_memory,
          [ "DevelopmentArtifactTitleChanged", 1 ] => post_remodel_development_memory,
          [ "GuidanceMessageAnchored", 1 ] => post_remodel_development_memory,
          [ "UserUtteranceForwardedByAgent", 2 ] => post_remodel_development_memory,
          [ "ResourceWorkIntentionDeclared", 1 ] => post_remodel_work_intention,
          [ "ResourceWorkIntentionExpired", 1 ] => post_remodel_work_intention,
          [ "ResourceWorkIntentionRenewed", 1 ] => post_remodel_work_intention,
          [ "ResourceWorkIntentionWithdrawn", 1 ] => post_remodel_work_intention,
          [ "WorkIntentionAddedToSet", 1 ] => post_remodel_work_intention,
          [ "WorkIntentionSetCreated", 1 ] => post_remodel_work_intention
        }.freeze
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:)
        schema_version = Integer(source_event.metadata.fetch("schema_version"))
        transformer = @definitions[[ source_event.type, schema_version ]]
        return Failure(unsupported(source_event, schema_version:)) unless transformer

        payload = @schema_registry.load(
          type: source_event.type,
          schema_version:,
          data: source_event.data
        )
        transformer.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload: payload
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(invalid(source_event, error:, schema_version: defined?(schema_version) ? schema_version : nil))
      end

      def registered_contracts
        @definitions.keys
      end

      private

      def unsupported(source_event, schema_version:)
        TransformationErrorV1.new(
          code: :unsupported_source_contract,
          message: "No historical transformation is registered for #{source_event.type}@#{schema_version}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end

      def invalid(source_event, error:, schema_version:)
        TransformationErrorV1.new(
          code: :invalid_source_event,
          message: "Historical source event is invalid: #{error.message}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end
    end
  end
end
