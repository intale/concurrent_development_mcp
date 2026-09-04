# frozen_string_literal: true

module Coordinator::Write
  class EventSchemaRegistry
    class UnknownSchema < KeyError; end
    class SchemaMismatch < ArgumentError; end

    DEFAULT_DEFINITIONS = {
      [ "RepositoryRegistered", 1 ] => Events::RepositoryRegisteredV1,
      [ "RepositoryRegistered", 2 ] => Events::RepositoryRegisteredV2,
      [ "RepositoryDisplayNameChanged", 1 ] => Events::RepositoryDisplayNameChangedV1,
      [ "RepositoryPathAdded", 1 ] => Events::RepositoryPathAddedV1,
      [ "RepositoryPathRemoved", 1 ] => Events::RepositoryPathRemovedV1,
      [ "RepositoryRemoteAdded", 1 ] => Events::RepositoryRemoteAddedV1,
      [ "RepositoryRemoteRemoved", 1 ] => Events::RepositoryRemoteRemovedV1,
      [ "ResourceRegistered", 1 ] => Events::ResourceIdentityV1::Registered,
      [ "ResourceRegistered", 2 ] => Events::ResourceIdentityV2::Registered,
      [ "ResourceBound", 1 ] => Events::ResourceIdentityV1::Bound,
      [ "ResourceBound", 2 ] => Events::ResourceIdentityV2::Bound,
      [ "ResourceUnbound", 1 ] => Events::ResourceIdentityV1::Unbound,
      [ "ResourceUnbound", 2 ] => Events::ResourceIdentityV2::Unbound,
      [ "ChangeSetCreated", 1 ] => Events::ChangeSetCreatedV1,
      [ "ChangeSetCreated", 2 ] => Events::ChangeSetCreatedV2,
      [ "ChangeSetGoalDefined", 1 ] => Events::ChangeSetGoalDefinedV1,
      [ "ChangeSetAcceptanceCriteriaDefined", 1 ] => Events::ChangeSetAcceptanceCriteriaDefinedV1,
      [ "ChangeSetAcceptanceCriteriaDefined", 2 ] => Events::ChangeSetAcceptanceCriteriaDefinedV2,
      [ "CommandRegistered", 1 ] => Events::CommandRegisteredV1,
      [ "CommandSucceeded", 1 ] => Events::CommandSucceededV1,
      [ "CommandRejected", 1 ] => Events::CommandRejectedV1,
      [ "ProcessStepPlanned", 1 ] => Events::ProcessStepPlannedV1,
      [ "SkillRegistered", 1 ] => Events::SkillRegisteredV1,
      [ "SkillRevisionCreated", 1 ] => Events::SkillRevisionCreatedV1,
      [ "SkillRevisionDescriptionDefined", 1 ] => Events::SkillRevisionDescriptionDefinedV1,
      [ "SkillRevisionInstructionsDefined", 1 ] => Events::SkillRevisionInstructionsDefinedV1,
      [ "SkillAssetCreated", 1 ] => Events::SkillAssetCreatedV1,
      [ "SkillAssetPathDefined", 1 ] => Events::SkillAssetPathDefinedV1,
      [ "SkillAssetContentDefined", 1 ] => Events::SkillAssetContentDefinedV1,
      [ "SkillAssetExecutabilityDefined", 1 ] => Events::SkillAssetExecutabilityDefinedV1,
      [ "SkillAssetAddedToRevision", 1 ] => Events::SkillAssetAddedToRevisionV1,
      [ "SkillRevisionPublished", 2 ] => Events::SkillRevisionPublishedV2,
      [ "SkillRevisionPublished", 3 ] => Events::SkillRevisionPublishedV3,
      [ "DevelopmentArtifactCaptured", 2 ] => Events::DevelopmentArtifactCapturedV2,
      [ "DevelopmentArtifactCreated", 1 ] => Events::DevelopmentArtifactCreatedV1,
      [ "DevelopmentArtifactScopeChanged", 1 ] => Events::DevelopmentArtifactScopeChangedV1,
      [ "DevelopmentArtifactTitleChanged", 1 ] => Events::DevelopmentArtifactTitleChangedV1,
      [ "DevelopmentArtifactKindChanged", 1 ] => Events::DevelopmentArtifactKindChangedV1,
      [ "DevelopmentArtifactLabelAdded", 1 ] => Events::DevelopmentArtifactLabelAddedV1,
      [ "DevelopmentArtifactLabelRemoved", 1 ] => Events::DevelopmentArtifactLabelRemovedV1,
      [ "DevelopmentArtifactSourceChanged", 1 ] => Events::DevelopmentArtifactSourceChangedV1,
      [ "DevelopmentArtifactContentChanged", 1 ] => Events::DevelopmentArtifactContentChangedV1,
      [ "DevelopmentArtifactObserved", 1 ] => Events::DevelopmentArtifactObservedV1,
      [ "DevelopmentArtifactObservationRecorded", 1 ] => Events::DevelopmentArtifactObservationRecordedV1,
      [ "DevelopmentArtifactObservationFactLinked", 1 ] => Events::DevelopmentArtifactObservationFactLinkedV1,
      [ "DevelopmentArtifactClassificationCorrected", 1 ] =>
        Events::DevelopmentArtifactClassificationCorrectedV1,
      [ "DevelopmentArtifactClassificationCorrectionRecorded", 1 ] =>
        Events::DevelopmentArtifactClassificationCorrectionRecordedV1,
      [ "DevelopmentArtifactRelationDeclared", 1 ] => Events::DevelopmentArtifactRelationDeclaredV1,
      [ "DevelopmentArtifactRelationDeclared", 2 ] => Events::DevelopmentArtifactRelationDeclaredV2,
      [ "DevelopmentArtifactRelationSuperseded", 1 ] => Events::DevelopmentArtifactRelationSupersededV1,
      [ "DevelopmentArtifactRelationSuperseded", 2 ] => Events::DevelopmentArtifactRelationSupersededV2,
      [ "OperationBatchCreated", 2 ] => Events::OperationBatchCreatedV2,
      [ "OperationBatchItemSucceeded", 2 ] => Events::OperationBatchItemSucceededV2,
      [ "OperationBatchItemRejected", 2 ] => Events::OperationBatchItemRejectedV2,
      [ "OperationBatchContinuationRequested", 2 ] => Events::OperationBatchContinuationRequestedV2,
      [ "OperationBatchCancellationRequested", 2 ] => Events::OperationBatchCancellationRequestedV2,
      [ "OperationBatchCancelled", 2 ] => Events::OperationBatchCancelledV2,
      [ "OperationBatchCompleted", 2 ] => Events::OperationBatchCompletedV2,
      [ "WorkItemCreated", 1 ] => Events::WorkItemCreatedV1,
      [ "WorkItemCreated", 2 ] => Events::WorkItemCreatedV2,
      [ "WorkItemAddedToChangeSet", 1 ] => Events::WorkItemAddedToChangeSetV1,
      [ "WorkItemAddedToChangeSet", 2 ] => Events::WorkItemAddedToChangeSetV2,
      [ "WorkItemAssignedToRepository", 1 ] => Events::WorkItemAssignedToRepositoryV1,
      [ "WorkItemGoalDefined", 1 ] => Events::WorkItemGoalDefinedV1,
      [ "WorkItemAcceptanceCriteriaDefined", 1 ] => Events::WorkItemAcceptanceCriteriaDefinedV1,
      [ "WorkItemCompetitiveModeSelected", 1 ] => Events::WorkItemCompetitiveModeSelectedV1,
      [ "WorkItemDependencyDeclared", 1 ] => Events::WorkItemDependencyDeclaredV1,
      [ "WorkItemDependencyDeclared", 2 ] => Events::WorkItemDependencyDeclaredV2,
      [ "WorkItemDependencySatisfied", 1 ] => Events::WorkItemDependencySatisfiedV1,
      [ "WorkItemDependencySatisfied", 2 ] => Events::WorkItemDependencySatisfiedV2,
      [ "ChangeSetActivated", 1 ] => Events::ChangeSetActivatedV1,
      [ "ChangeSetActivated", 2 ] => Events::ChangeSetActivatedV2,
      [ "ChangeSetReleaseSetLinked", 1 ] => Events::ChangeSetReleaseSetLinkedV1,
      [ "ChangeSetCompleted", 1 ] => Events::ChangeSetCompletedV1,
      [ "ChangeSetCompleted", 2 ] => Events::ChangeSetCompletedV2,
      [ "WorkItemMadeReady", 1 ] => Events::WorkItemMadeReadyV1,
      [ "WorkItemMadeReady", 2 ] => Events::WorkItemMadeReadyV2,
      [ "WorkItemAcquired", 1 ] => Events::WorkItemAcquiredV1,
      [ "WorkItemAcquired", 2 ] => Events::WorkItemAcquiredV2,
      [ "WorkItemRequeued", 1 ] => Events::WorkItemRequeuedV1,
      [ "WorkItemRequeued", 2 ] => Events::WorkItemRequeuedV2,
      [ "WorkItemCandidateSelected", 1 ] => Events::WorkItemCandidateSelectedV1,
      [ "WorkItemCandidateSelected", 2 ] => Events::WorkItemCandidateSelectedV2,
      [ "WorkItemOutputRecorded", 1 ] => Events::WorkItemOutputRecordedV1,
      [ "WorkItemCompleted", 1 ] => Events::WorkItemCompletedV1,
      [ "WorkItemCompleted", 2 ] => Events::WorkItemCompletedV2,
      [ "AttemptAuthorized", 1 ] => Events::AttemptAuthorizedV1,
      [ "AttemptAuthorized", 2 ] => Events::AttemptAuthorizedV2,
      [ "AttemptAssignedToWorkItem", 1 ] => Events::AttemptAssignedToWorkItemV1,
      [ "AttemptAssignedToAgent", 1 ] => Events::AttemptAssignedToAgentV1,
      [ "AttemptBaseSnapshotRecorded", 1 ] => Events::AttemptBaseSnapshotRecordedV1,
      [ "AttemptStarted", 1 ] => Events::AttemptStartedV1,
      [ "AttemptStarted", 2 ] => Events::AttemptStartedV2,
      [ "AttemptAbandoned", 2 ] => Events::AttemptAbandonedV2,
      [ "AttemptAbandoned", 3 ] => Events::AttemptAbandonedV3,
      [ "AttemptCompleted", 1 ] => Events::AttemptCompletedV1,
      [ "AttemptCompleted", 2 ] => Events::AttemptCompletedV2,
      [ "WorkIntentionSetCreated", 1 ] => Events::WorkIntentionSetCreatedV1,
      [ "WorkIntentionAddedToSet", 1 ] => Events::WorkIntentionAddedToSetV1,
      [ "ResourceWorkIntentionDeclared", 1 ] => Events::ResourceWorkIntentionDeclaredV1,
      [ "ResourceWorkIntentionRenewed", 1 ] => Events::ResourceWorkIntentionRenewedV1,
      [ "ResourceWorkIntentionWithdrawn", 1 ] => Events::ResourceWorkIntentionWithdrawnV1,
      [ "ResourceWorkIntentionExpired", 1 ] => Events::ResourceWorkIntentionExpiredV1,
      [ "ResourceLeaseAcquired", 2 ] => Events::ResourceLeaseAcquiredV2,
      [ "ResourceLeaseRenewed", 2 ] => Events::ResourceLeaseRenewedV2,
      [ "ResourceLeaseReleased", 2 ] => Events::ResourceLeaseReleasedV2,
      [ "ResourceLeaseExpired", 2 ] => Events::ResourceLeaseExpiredV2,
      [ "ResourceBoundaryEpochRolled", 2 ] => Events::ResourceBoundaryEpochRolledV2,
      [ "WriteSetReserved", 2 ] => Events::WriteSetReservedV2,
      [ "WriteSetExpanded", 2 ] => Events::WriteSetExpandedV2,
      [ "WriteSetRenewed", 2 ] => Events::WriteSetRenewedV2,
      [ "WriteSetReleased", 2 ] => Events::WriteSetReleasedV2,
      [ "UserUtteranceRecorded", 1 ] => Events::UserUtteranceRecordedV1,
      [ "UserUtteranceRecorded", 2 ] => Events::UserUtteranceRecordedV2,
      [ "UserUtteranceForwardedByAgent", 1 ] => Events::UserUtteranceForwardedByAgentV1,
      [ "UserUtteranceForwardedByAgent", 2 ] => Events::UserUtteranceForwardedByAgentV2,
      [ "GuidanceMessageAnchored", 1 ] => Events::GuidanceMessageAnchoredV1,
      [ "DecisionInterpretationProposed", 1 ] => Events::DecisionInterpretationProposedV1,
      [ "DecisionInterpretationProposed", 2 ] => Events::DecisionInterpretationProposedV2,
      [ "DecisionClarificationRequired", 1 ] => Events::DecisionClarificationRequiredV1,
      [ "DecisionClarificationRequired", 2 ] => Events::DecisionClarificationRequiredV2,
      [ "DecisionInterpretationAccepted", 1 ] => Events::DecisionInterpretationAcceptedV1,
      [ "DecisionInterpretationAccepted", 2 ] => Events::DecisionInterpretationAcceptedV2,
      [ "DecisionInterpretationRejected", 1 ] => Events::DecisionInterpretationRejectedV1,
      [ "DecisionInterpretationRejected", 2 ] => Events::DecisionInterpretationRejectedV2,
      [ "DecisionRecorded", 1 ] => Events::DecisionRecordedV1,
      [ "DecisionRecorded", 2 ] => Events::DecisionRecordedV2,
      [ "DecisionDerivedFromInterpretation", 1 ] => Events::DecisionDerivedFromInterpretationV1,
      [ "DecisionActivated", 1 ] => Events::DecisionActivatedV1,
      [ "DecisionActivated", 2 ] => Events::DecisionActivatedV2,
      [ "DecisionDefinitionCorrected", 1 ] => Events::DecisionDefinitionCorrectedV1,
      [ "DecisionDefinitionCorrected", 2 ] => Events::DecisionDefinitionCorrectedV2,
      [ "DecisionSlotOpened", 1 ] => Events::DecisionSlotOpenedV1,
      [ "DecisionSlotOpened", 2 ] => Events::DecisionSlotOpenedV2,
      [ "DecisionSlotHeadChanged", 1 ] => Events::DecisionSlotHeadChangedV1,
      [ "DecisionSlotHeadChanged", 2 ] => Events::DecisionSlotHeadChangedV2,
      [ "DecisionPartitionAdvanced", 1 ] => Events::DecisionPartitionAdvancedV1,
      [ "DecisionAddedToPartition", 1 ] => Events::DecisionAddedToPartitionV1,
      [ "DecisionRemovedFromPartition", 1 ] => Events::DecisionRemovedFromPartitionV1,
      [ "AgentChoiceRecorded", 1 ] => Events::AgentChoiceRecordedV1,
      [ "AgentChoiceRecorded", 2 ] => Events::AgentChoiceRecordedV2,
      [ "AgentChoiceAccepted", 1 ] => Events::AgentChoiceAcceptedV1,
      [ "AgentChoiceAccepted", 2 ] => Events::AgentChoiceAcceptedV2,
      [ "AgentChoiceImpactScanStarted", 1 ] => Events::AgentChoiceImpactScanStartedV1,
      [ "AgentChoiceImpactScanSkipped", 1 ] => Events::AgentChoiceImpactScanSkippedV1,
      [ "AgentChoiceImpactScanProgressed", 1 ] => Events::AgentChoiceImpactScanProgressedV1,
      [ "AgentChoiceImpactScanCompleted", 1 ] => Events::AgentChoiceImpactScanCompletedV1,
      [ "AgentChoiceImpactAssessed", 1 ] => Events::AgentChoiceImpactAssessedV1,
      [ "AgentChoiceImpactAssessmentRecorded", 1 ] => Events::AgentChoiceImpactAssessmentRecordedV1,
      [ "AgentChoiceImpactSourceLinked", 1 ] => Events::AgentChoiceImpactSourceLinkedV1,
      [ "AgentChoiceInvalidatedByDecision", 1 ] => Events::AgentChoiceInvalidatedByDecisionV1,
      [ "AgentChoiceInvalidatedByDecision", 2 ] => Events::AgentChoiceInvalidatedByDecisionV2,
      [ "CandidateSubmitted", 2 ] => Events::CandidateSubmittedV2,
      [ "CandidateChangeManifestCaptured", 1 ] => Events::CandidateChangeManifestCapturedV1,
      [ "CandidateBuildContextCaptured", 1 ] => Events::CandidateBuildContextCapturedV1,
      [ "CandidateImpactSurfaceDerived", 1 ] => Events::CandidateImpactSurfaceDerivedV1,
      [ "CandidateImpactSurfaceRegistered", 1 ] => Events::CandidateImpactSurfaceRegisteredV1,
      [ "CandidateImpactRegistrySweepStarted", 1 ] => Events::CandidateImpactRegistrySweepStartedV1,
      [ "CandidateImpactRegistrySweepSkipped", 1 ] => Events::CandidateImpactRegistrySweepSkippedV1,
      [ "CandidateImpactRegistrySweepProgressed", 1 ] => Events::CandidateImpactRegistrySweepProgressedV1,
      [ "CandidateImpactRegistrySweepCompleted", 1 ] => Events::CandidateImpactRegistrySweepCompletedV1,
      [ "CandidateImpactPairScanStarted", 1 ] => Events::CandidateImpactPairScanStartedV1,
      [ "CandidateImpactPairScanSkipped", 1 ] => Events::CandidateImpactPairScanSkippedV1,
      [ "CandidateImpactPairScanProgressed", 1 ] => Events::CandidateImpactPairScanProgressedV1,
      [ "CandidateImpactPairScanCompleted", 1 ] => Events::CandidateImpactPairScanCompletedV1,
      [ "VerificationObligationCreated", 1 ] => Events::VerificationObligationCreatedV1,
      [ "VerificationObligationClaimed", 1 ] => Events::VerificationObligationClaimedV1,
      [ "VerificationEvidenceSubmitted", 1 ] => Events::VerificationEvidenceSubmittedV1,
      [ "VerificationObligationSatisfied", 1 ] => Events::VerificationObligationSatisfiedV1,
      [ "VerificationObligationFailed", 1 ] => Events::VerificationObligationFailedV1,
      [ "VerificationObligationWaived", 1 ] => Events::VerificationObligationWaivedV1,
      [ "VerificationObligationInvalidated", 1 ] => Events::VerificationObligationInvalidatedV1,
      [ "VerificationObligationValidityScanStarted", 1 ] => Events::VerificationObligationValidityScanStartedV1,
      [ "VerificationObligationValidityScanProgressed", 1 ] => Events::VerificationObligationValidityScanProgressedV1,
      [ "VerificationObligationValidityScanCompleted", 1 ] => Events::VerificationObligationValidityScanCompletedV1,
      [ "CandidateHeadRegistered", 1 ] => Events::CandidateHeadRegisteredV1,
      [ "CandidateHeadRegistered", 2 ] => Events::CandidateHeadRegisteredV2,
      [ "CandidateAttachedToAttempt", 1 ] => Events::CandidateAttachedToAttemptV1,
      [ "MergeSnapshotRegistered", 1 ] => Events::MergeSnapshotRegisteredV1,
      [ "MergeSnapshotCommitRegistered", 1 ] => Events::MergeSnapshotCommitRegisteredV1,
      [ "MergeSnapshotCommitRegistered", 2 ] => Events::MergeSnapshotCommitRegisteredV2,
      [ "MergeSnapshotVerificationSubmitted", 1 ] => Events::MergeSnapshotVerificationSubmittedV1,
      [ "MergeSnapshotVerified", 1 ] => Events::MergeSnapshotVerifiedV1,
      [ "MergeAuthorizationGranted", 1 ] => Events::MergeAuthorizationGrantedV1,
      [ "MergeAuthorizationDenied", 1 ] => Events::MergeAuthorizationDeniedV1,
      [ "MergeObserved", 1 ] => Events::MergeObservedV1,
      [ "ReleaseSetPrepared", 1 ] => Events::ReleaseSetPreparedV1,
      [ "RepositoryIntegrationRecorded", 1 ] => Events::RepositoryIntegrationRecordedV1,
      [ "ReleaseSetVerificationRecorded", 1 ] => Events::ReleaseSetVerificationRecordedV1,
      [ "ReleaseSetActivated", 1 ] => Events::ReleaseSetActivatedV1,
      [ "ReleaseSetCompensationRequested", 1 ] => Events::ReleaseSetCompensationRequestedV1,
      [ "ReleaseSetCompleted", 1 ] => Events::ReleaseSetCompletedV1,
      [ "CoordinationTaskSubmitted", 3 ] => Events::CoordinationTaskSubmittedV3,
      [ "CoordinationTaskExecutionStarted", 2 ] => Events::CoordinationTaskExecutionStartedV2,
      [ "CoordinationTaskCompleted", 3 ] => Events::CoordinationTaskCompletedV3,
      [ "CoordinationTaskFailed", 2 ] => Events::CoordinationTaskFailedV2,
      [ "CoordinationTaskCancellationRequested", 2 ] => Events::CoordinationTaskCancellationRequestedV2,
      [ "CoordinationTaskCancelled", 2 ] => Events::CoordinationTaskCancelledV2
    }.freeze

    DEFAULT_VALIDATORS = {
      Events::CoordinationTaskSubmittedV3 => Contracts::CoordinationTaskSubmission.new
    }.freeze

    def initialize(definitions: DEFAULT_DEFINITIONS, validators: DEFAULT_VALIDATORS)
      @definitions = definitions.dup.freeze
      @validators = validators.dup.freeze
    end

    def fetch(type:, schema_version:)
      @definitions.fetch([ type, schema_version ]) do
        raise UnknownSchema, "unknown event schema: #{type}@#{schema_version}"
      end
    end

    def verify!(event)
      fetch(type: event.class.event_type, schema_version: event.class.schema_version)
      validate!(event)
      event
    end

    def load(type:, schema_version:, data:)
      payload_class = fetch(type:, schema_version:)
      payload = payload_class.new(deep_symbolize(data))
      validate!(payload)
      payload
    end

    private

    def validate!(event)
      validator = @validators[event.class]
      return unless validator

      result = validator.call(event:)
      raise InvalidCoordinationTaskSubmission, result.errors.to_h.inspect if result.failure?
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), output|
          symbol_key = key.to_sym
          raise SchemaMismatch, "duplicate payload key: #{symbol_key.inspect}" if output.key?(symbol_key)

          output[symbol_key] = deep_symbolize(nested)
        end
      when Array
        value.map { deep_symbolize(_1) }
      else
        value
      end
    end
  end
end
