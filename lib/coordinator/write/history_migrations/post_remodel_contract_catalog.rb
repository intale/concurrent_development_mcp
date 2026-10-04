# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelContractCatalog
      REPOSITORY_CONTRACTS = %w[
        RepositoryRegistered@2 RepositoryDisplayNameChanged@1 RepositoryPathAdded@1
        RepositoryPathRemoved@1 RepositoryRemoteAdded@1 RepositoryRemoteRemoved@1
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      PLANNING_CONTRACTS = %w[
        AttemptAbandoned@3 AttemptAssignedToAgent@1 AttemptAssignedToWorkItem@1 AttemptAuthorized@2
        AttemptBaseSnapshotRecorded@1 AttemptCompleted@2 AttemptStarted@2 CandidateAssignedToAttempt@1
        CandidateAssignedToRepository@1 CandidateChangeManifestCaptured@2 CandidateCheckpointKindSelected@1
        CandidateCommitRangeDeclared@1 CandidateCreated@1 CandidateHeadRegistered@2 CandidateSubmitted@3
        CandidateTargetBranchSelected@1 CandidateWorkIntentionSetAssigned@1 WorkItemAcquired@2
        WorkItemCandidateSelected@2 WorkItemCompleted@2 WorkItemDependencySatisfied@2 WorkItemMadeReady@2
        WorkItemRequeued@2
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      COMMAND_AND_TASK_CONTRACTS = %w[
        CommandRegistered@1 CommandRejected@1 CommandRejected@2 CommandSucceeded@1
        CoordinationTaskCompleted@3 CoordinationTaskExecutionStarted@2 CoordinationTaskSubmitted@3
        ProcessStepPlanned@1
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      DEVELOPMENT_MEMORY_CONTRACTS = %w[
        DevelopmentArtifactContentChanged@1 DevelopmentArtifactCreated@1 DevelopmentArtifactKindChanged@1
        DevelopmentArtifactLabelAdded@1 DevelopmentArtifactObservationFactLinked@1
        DevelopmentArtifactObservationRecorded@1 DevelopmentArtifactRelationDeclared@2
        DevelopmentArtifactScopeChanged@1 DevelopmentArtifactSourceChanged@1 DevelopmentArtifactTitleChanged@1
        GuidanceMessageAnchored@1 UserUtteranceForwardedByAgent@2
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      WORK_INTENTION_CONTRACTS = %w[
        ResourceWorkIntentionDeclared@1 ResourceWorkIntentionExpired@1 ResourceWorkIntentionRenewed@1
        ResourceWorkIntentionWithdrawn@1 WorkIntentionAddedToSet@1 WorkIntentionSetCreated@1
      ].map do |contract|
        type, version = contract.split("@", 2)
        [ type.freeze, Integer(version) ].freeze
      end.freeze

      SOURCE_CONTRACTS = [
        *REPOSITORY_CONTRACTS,
        *PLANNING_CONTRACTS,
        *COMMAND_AND_TASK_CONTRACTS,
        *DEVELOPMENT_MEMORY_CONTRACTS,
        *WORK_INTENTION_CONTRACTS
      ].freeze

      def source_contracts
        SOURCE_CONTRACTS
      end

      def include?(type:, schema_version:)
        SOURCE_CONTRACTS.include?([ type, schema_version ])
      end
    end
  end
end
