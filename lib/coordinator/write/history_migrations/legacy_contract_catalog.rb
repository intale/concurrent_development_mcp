# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyContractCatalog
      SOURCE_CONTRACTS = %w[
        AgentChoiceAccepted@1 AgentChoiceImpactAssessed@1 AgentChoiceImpactScanCompleted@1 AgentChoiceImpactScanProgressed@1
        AgentChoiceImpactScanSkipped@1 AgentChoiceImpactScanStarted@1 AgentChoiceInvalidatedByDecision@1 AgentChoiceRecorded@1
        AttemptAbandoned@2 AttemptAuthorized@1 AttemptCompleted@1 AttemptStarted@1
        CandidateAttachedToAttempt@1 CandidateBuildContextCaptured@1 CandidateChangeManifestCaptured@1 CandidateHeadRegistered@1
        CandidateImpactPairScanCompleted@1 CandidateImpactPairScanProgressed@1 CandidateImpactPairScanSkipped@1 CandidateImpactPairScanStarted@1
        CandidateImpactRegistrySweepCompleted@1 CandidateImpactRegistrySweepProgressed@1 CandidateImpactRegistrySweepSkipped@1 CandidateImpactRegistrySweepStarted@1
        CandidateImpactSurfaceDerived@1 CandidateImpactSurfaceRegistered@1 CandidateSubmitted@2 ChangeSetAcceptanceCriteriaDefined@1
        ChangeSetActivated@1 ChangeSetCompleted@1 ChangeSetCreated@1 CommandCompleted@1
        CoordinationTaskCancellationRequested@1 CoordinationTaskCancelled@1 CoordinationTaskCompleted@2 CoordinationTaskExecutionStarted@1
        CoordinationTaskFailed@1 CoordinationTaskSubmitted@2 DecisionActivated@1 DecisionClarificationRequired@1
        DecisionDefinitionCorrected@1 DecisionInterpretationAccepted@1 DecisionInterpretationProposed@1 DecisionInterpretationRejected@1
        DecisionPartitionAdvanced@1 DecisionRecorded@1 DecisionSlotHeadChanged@1 DecisionSlotOpened@1
        DevelopmentArtifactCaptured@2 DevelopmentArtifactClassificationCorrected@1 DevelopmentArtifactObserved@1 DevelopmentArtifactRelationDeclared@1
        DevelopmentArtifactRelationSuperseded@1 MergeAuthorizationDenied@1 MergeAuthorizationGranted@1 MergeObserved@1
        MergeSnapshotCommitRegistered@1 MergeSnapshotRegistered@1 MergeSnapshotVerificationSubmitted@1 MergeSnapshotVerified@1
        OperationBatchCancellationRequested@1 OperationBatchCancelled@1 OperationBatchCompleted@1 OperationBatchContinuationRequested@1
        OperationBatchCreated@1 OperationBatchItemRejected@1 OperationBatchItemSucceeded@1 ReleaseSetActivated@1
        ReleaseSetCompensationRequested@1 ReleaseSetCompleted@1 ReleaseSetPrepared@1 ReleaseSetVerificationRecorded@1
        RepositoryIntegrationRecorded@1 RepositoryRegistered@1 ResourceBound@1 ResourceBoundaryEpochRolled@2
        ResourceLeaseAcquired@2 ResourceLeaseExpired@2 ResourceLeaseReleased@2 ResourceLeaseRenewed@2
        ResourceRegistered@1 ResourceUnbound@1 SkillRevisionPublished@2 UserUtteranceForwardedByAgent@1
        UserUtteranceRecorded@1 VerificationEvidenceSubmitted@1 VerificationObligationClaimed@1 VerificationObligationCreated@1
        VerificationObligationFailed@1 VerificationObligationInvalidated@1 VerificationObligationSatisfied@1 VerificationObligationValidityScanCompleted@1
        VerificationObligationValidityScanProgressed@1 VerificationObligationValidityScanStarted@1 VerificationObligationWaived@1 WorkItemAcquired@1
        WorkItemAddedToChangeSet@1 WorkItemCandidateSelected@1 WorkItemCompleted@1 WorkItemCreated@1
        WorkItemDependencyDeclared@1 WorkItemDependencySatisfied@1 WorkItemMadeReady@1 WorkItemRequeued@1
        WriteSetExpanded@2 WriteSetReleased@2 WriteSetRenewed@2 WriteSetReserved@2
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      def source_contracts
        SOURCE_CONTRACTS
      end

      def include?(type:, schema_version:)
        SOURCE_CONTRACTS.include?([ type, schema_version ])
      end
    end
  end
end
