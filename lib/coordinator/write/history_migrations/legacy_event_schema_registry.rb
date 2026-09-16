# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyEventSchemaRegistry
      HISTORICAL_DEFINITIONS = {
        [ "AgentChoiceImpactScanCompleted", 1 ] => Events::AgentChoiceImpactScanCompletedV1,
        [ "AgentChoiceImpactScanProgressed", 1 ] => Events::AgentChoiceImpactScanProgressedV1,
        [ "AgentChoiceImpactScanSkipped", 1 ] => Events::AgentChoiceImpactScanSkippedV1,
        [ "AgentChoiceImpactScanStarted", 1 ] => Events::AgentChoiceImpactScanStartedV1,
        [ "CandidateAttachedToAttempt", 1 ] => Events::CandidateAttachedToAttemptV1,
        [ "CandidateBuildContextCaptured", 1 ] => Events::CandidateBuildContextCapturedV1,
        [ "CandidateChangeManifestCaptured", 1 ] => Events::CandidateChangeManifestCapturedV1,
        [ "CandidateImpactPairScanCompleted", 1 ] => Events::CandidateImpactPairScanCompletedV1,
        [ "CandidateImpactPairScanProgressed", 1 ] => Events::CandidateImpactPairScanProgressedV1,
        [ "CandidateImpactPairScanSkipped", 1 ] => Events::CandidateImpactPairScanSkippedV1,
        [ "CandidateImpactPairScanStarted", 1 ] => Events::CandidateImpactPairScanStartedV1,
        [ "CandidateImpactRegistrySweepCompleted", 1 ] => Events::CandidateImpactRegistrySweepCompletedV1,
        [ "CandidateImpactRegistrySweepProgressed", 1 ] => Events::CandidateImpactRegistrySweepProgressedV1,
        [ "CandidateImpactRegistrySweepSkipped", 1 ] => Events::CandidateImpactRegistrySweepSkippedV1,
        [ "CandidateImpactRegistrySweepStarted", 1 ] => Events::CandidateImpactRegistrySweepStartedV1,
        [ "CandidateImpactSurfaceDerived", 1 ] => Events::CandidateImpactSurfaceDerivedV1,
        [ "CandidateImpactSurfaceRegistered", 1 ] => Events::CandidateImpactSurfaceRegisteredV1,
        [ "CandidateSubmitted", 2 ] => Events::CandidateSubmittedV2,
        [ "CommandCompleted", 1 ] => LegacyEvents::CommandCompletedV1,
        [ "CoordinationTaskCancellationRequested", 1 ] => LegacyEvents::CoordinationTaskCancellationRequestedV1,
        [ "CoordinationTaskCancelled", 1 ] => LegacyEvents::CoordinationTaskCancelledV1,
        [ "CoordinationTaskCompleted", 2 ] => LegacyEvents::CoordinationTaskCompletedV2,
        [ "CoordinationTaskExecutionStarted", 1 ] => LegacyEvents::CoordinationTaskExecutionStartedV1,
        [ "CoordinationTaskFailed", 1 ] => LegacyEvents::CoordinationTaskFailedV1,
        [ "CoordinationTaskSubmitted", 2 ] => LegacyEvents::CoordinationTaskSubmittedV2,
        [ "DecisionActivated", 1 ] => LegacyEvents::DecisionActivatedV1,
        [ "DecisionDefinitionCorrected", 1 ] => LegacyEvents::DecisionDefinitionCorrectedV1,
        [ "DecisionSlotOpened", 1 ] => LegacyEvents::DecisionSlotOpenedV1,
        [ "MergeAuthorizationDenied", 1 ] => Events::MergeAuthorizationDeniedV1,
        [ "MergeAuthorizationGranted", 1 ] => Events::MergeAuthorizationGrantedV1,
        [ "MergeObserved", 1 ] => Events::MergeObservedV1,
        [ "MergeSnapshotCommitRegistered", 1 ] => Events::MergeSnapshotCommitRegisteredV1,
        [ "MergeSnapshotRegistered", 1 ] => Events::MergeSnapshotRegisteredV1,
        [ "MergeSnapshotVerificationSubmitted", 1 ] => Events::MergeSnapshotVerificationSubmittedV1,
        [ "MergeSnapshotVerified", 1 ] => Events::MergeSnapshotVerifiedV1,
        [ "OperationBatchCancellationRequested", 1 ] => LegacyEvents::OperationBatchCancellationRequestedV1,
        [ "OperationBatchCancelled", 1 ] => LegacyEvents::OperationBatchCancelledV1,
        [ "OperationBatchCompleted", 1 ] => LegacyEvents::OperationBatchCompletedV1,
        [ "OperationBatchContinuationRequested", 1 ] => LegacyEvents::OperationBatchContinuationRequestedV1,
        [ "OperationBatchCreated", 1 ] => LegacyEvents::OperationBatchCreatedV1,
        [ "OperationBatchItemRejected", 1 ] => LegacyEvents::OperationBatchItemRejectedV1,
        [ "OperationBatchItemSucceeded", 1 ] => LegacyEvents::OperationBatchItemSucceededV1,
        [ "ReleaseSetActivated", 1 ] => Events::ReleaseSetActivatedV1,
        [ "ReleaseSetCompensationRequested", 1 ] => Events::ReleaseSetCompensationRequestedV1,
        [ "ReleaseSetCompleted", 1 ] => Events::ReleaseSetCompletedV1,
        [ "ReleaseSetPrepared", 1 ] => Events::ReleaseSetPreparedV1,
        [ "ReleaseSetVerificationRecorded", 1 ] => Events::ReleaseSetVerificationRecordedV1,
        [ "RepositoryIntegrationRecorded", 1 ] => Events::RepositoryIntegrationRecordedV1,
        [ "VerificationObligationValidityScanCompleted", 1 ] => Events::VerificationObligationValidityScanCompletedV1,
        [ "VerificationObligationValidityScanProgressed", 1 ] => Events::VerificationObligationValidityScanProgressedV1,
        [ "VerificationObligationValidityScanStarted", 1 ] => Events::VerificationObligationValidityScanStartedV1
      }.freeze

      CURRENT_DEFINITIONS = EventSchemaRegistry::DEFAULT_DEFINITIONS.slice(*LegacyContractCatalog::SOURCE_CONTRACTS).freeze
      DEFINITIONS = CURRENT_DEFINITIONS.merge(HISTORICAL_DEFINITIONS).freeze

      def initialize(registry: EventSchemaRegistry.new(definitions: DEFINITIONS, validators: {}))
        @registry = registry
      end

      def fetch(type:, schema_version:)
        @registry.fetch(type:, schema_version:)
      end

      def load(type:, schema_version:, data:)
        @registry.load(type:, schema_version:, data:)
      end
    end
  end
end
