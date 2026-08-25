# frozen_string_literal: true

module Coordinator::Write
  module EventQueries
    GUIDANCE_MESSAGE_EVENT_TYPES = [
      "UserUtteranceRecorded",
      "UserUtteranceForwardedByAgent"
    ].freeze

    def self.guidance_message(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Conversation",
        event_types: GUIDANCE_MESSAGE_EVENT_TYPES,
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_proposal(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationProposed" ],
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_terminal(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted", "DecisionInterpretationRejected" ],
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_slot_acceptance(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted" ],
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_acceptance(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted" ],
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.decision_activation(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Decision",
        event_types: [ "DecisionActivated" ],
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.candidate_impact_surface_registration(marker)
      MarkedEventReadCriteria.new(
        event_type: "CandidateImpactSurfaceRegistered",
        marker:,
        maximum_count: 1,
        direction: :asc
      )
    end

    COMMAND_COMPLETION = EventReadCriteria.new(
      event_types: [ "CommandCompleted" ],
      maximum_count: 1,
      direction: :desc
    )

    SKILL_LATEST_REVISION = GroupedEventReadCriteria.new(
      event_types: [ "SkillRevisionPublished" ],
      direction: :desc
    )

    DEVELOPMENT_ARTIFACT_HISTORY = EventReadCriteria.new(
      event_types: [ "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared" ],
      maximum_count: Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT + 1,
      direction: :asc
    )

    DEVELOPMENT_ARTIFACT_CAPTURE = EventReadCriteria.new(
      event_types: [ "DevelopmentArtifactCaptured" ],
      maximum_count: 1,
      direction: :asc
    )

    OPERATION_BATCH_HISTORY = EventReadCriteria.new(
      event_types: [
        "OperationBatchCreated",
        "OperationBatchItemSucceeded",
        "OperationBatchItemRejected",
        "OperationBatchContinuationRequested",
        "OperationBatchCancellationRequested",
        "OperationBatchCancelled",
        "OperationBatchCompleted"
      ],
      maximum_count: Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS,
      direction: :asc
    )

    DECISION_EXISTENCE = EventReadCriteria.new(
      event_types: [ "DecisionRecorded", "DecisionActivated" ],
      maximum_count: 2,
      direction: :asc
    )

    DECISION_CORRECTION_STATE = GroupedEventReadCriteria.new(
      event_types: [ "DecisionRecorded", "DecisionActivated", "DecisionDefinitionCorrected" ],
      direction: :desc
    )

    DECISION_LATEST_IMPACT_CHANGE = GroupedEventReadCriteria.new(
      event_types: [ "DecisionActivated", "DecisionDefinitionCorrected" ],
      direction: :desc
    )

    DECISION_SLOT_LATEST = GroupedEventReadCriteria.new(
      event_types: [ "DecisionSlotOpened", "DecisionSlotHeadChanged" ],
      direction: :desc
    )

    DECISION_PARTITION_LATEST = GroupedEventReadCriteria.new(
      event_types: [ "DecisionPartitionAdvanced" ],
      direction: :desc
    )

    AGENT_CHOICE_EXISTENCE = EventReadCriteria.new(
      event_types: [ "AgentChoiceRecorded", "AgentChoiceAccepted" ],
      maximum_count: 2,
      direction: :asc
    )

    AGENT_CHOICE_IMPACT_SCAN_STATE = GroupedEventReadCriteria.new(
      event_types: [
        "AgentChoiceImpactScanStarted",
        "AgentChoiceImpactScanSkipped",
        "AgentChoiceImpactScanProgressed",
        "AgentChoiceImpactScanCompleted"
      ],
      direction: :desc
    )

    AGENT_CHOICE_FOR_IMPACT = EventReadCriteria.new(
      event_types: [
        "AgentChoiceRecorded",
        "AgentChoiceAccepted",
        "AgentChoiceInvalidatedByDecision"
      ],
      maximum_count: 3,
      direction: :asc
    )

    AGENT_CHOICE_IMPACT_ASSESSMENT = EventReadCriteria.new(
      event_types: [ "AgentChoiceImpactAssessed" ],
      maximum_count: 1,
      direction: :asc
    )

    ATTEMPT_FOR_AGENT_CHOICE = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted" ],
      maximum_count: 2,
      direction: :asc
    )

    CANDIDATE_EXISTENCE = EventReadCriteria.new(
      event_types: [ "CandidateSubmitted" ],
      maximum_count: 1,
      direction: :asc
    )

    CANDIDATE_FOR_WORK_ITEM_COMPLETION = EventReadCriteria.new(
      event_types: [ "CandidateSubmitted" ],
      maximum_count: 1,
      direction: :asc
    )

    CANDIDATE_HEAD_REGISTRATION = EventReadCriteria.new(
      event_types: [ "CandidateHeadRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    CANDIDATE_FOR_MERGE_SNAPSHOT = EventReadCriteria.new(
      event_types: [ "CandidateSubmitted", "CandidateChangeManifestCaptured" ],
      maximum_count: 2,
      direction: :asc
    )

    MERGE_SNAPSHOT_REGISTRATION = EventReadCriteria.new(
      event_types: [ "MergeSnapshotRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    MERGE_SNAPSHOT_COMMIT_REGISTRATION = EventReadCriteria.new(
      event_types: [ "MergeSnapshotCommitRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    MERGE_SNAPSHOT_VERIFICATION_HISTORY = EventReadCriteria.new(
      event_types: [ "MergeSnapshotVerificationSubmitted" ],
      maximum_count: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT + 1,
      direction: :asc
    )

    MERGE_SNAPSHOT_VERIFIED = EventReadCriteria.new(
      event_types: [ "MergeSnapshotVerified" ],
      maximum_count: 1,
      direction: :asc
    )

    MERGE_OBSERVATION = EventReadCriteria.new(
      event_types: [ "MergeObserved" ],
      maximum_count: 1,
      direction: :asc
    )

    RELEASE_SET_PREPARATION = EventReadCriteria.new(
      event_types: [ "ReleaseSetPrepared" ],
      maximum_count: 1,
      direction: :asc
    )

    RELEASE_SET_LIFECYCLE = EventReadCriteria.new(
      event_types: [
        "ReleaseSetPrepared",
        "RepositoryIntegrationRecorded",
        "ReleaseSetVerificationRecorded",
        "ReleaseSetActivated",
        "ReleaseSetCompensationRequested",
        "ReleaseSetCompleted"
      ],
      maximum_count: Types::RELEASE_SET_LIFECYCLE_MAXIMUM_EVENTS,
      direction: :asc
    )

    CANDIDATE_FOR_IMPACT_SURFACE = GroupedEventReadCriteria.new(
      event_types: [
        "CandidateSubmitted",
        "CandidateChangeManifestCaptured",
        "CandidateBuildContextCaptured",
        "CandidateImpactSurfaceDerived"
      ],
      direction: :asc
    )

    VERIFICATION_OBLIGATION_CREATION = EventReadCriteria.new(
      event_types: [ "VerificationObligationCreated" ],
      maximum_count: 1,
      direction: :asc
    )

    VERIFICATION_OBLIGATION_FOR_CLAIM = GroupedEventReadCriteria.new(
      event_types: [
        "VerificationObligationCreated",
        "VerificationObligationClaimed",
        "VerificationObligationSatisfied",
        "VerificationObligationFailed",
        "VerificationObligationWaived",
        "VerificationObligationInvalidated"
      ],
      direction: :desc
    )

    VERIFICATION_OBLIGATION_FOR_EVIDENCE = GroupedEventReadCriteria.new(
      event_types: [
        "VerificationObligationCreated",
        "VerificationObligationClaimed",
        "VerificationObligationSatisfied",
        "VerificationObligationFailed",
        "VerificationObligationWaived",
        "VerificationObligationInvalidated"
      ],
      direction: :desc
    )

    VERIFICATION_OBLIGATION_LIFECYCLE = GroupedEventReadCriteria.new(
      event_types: [
        "VerificationObligationCreated",
        "VerificationObligationSatisfied",
        "VerificationObligationFailed",
        "VerificationObligationWaived",
        "VerificationObligationInvalidated"
      ],
      direction: :desc
    )

    VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATE = GroupedEventReadCriteria.new(
      event_types: [
        "VerificationObligationValidityScanStarted",
        "VerificationObligationValidityScanProgressed",
        "VerificationObligationValidityScanCompleted"
      ],
      direction: :desc
    )

    VERIFICATION_EVIDENCE_HISTORY = EventReadCriteria.new(
      event_types: [ "VerificationEvidenceSubmitted" ],
      maximum_count: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT,
      direction: :asc
    )

    CANDIDATE_IMPACT_REGISTRY_LATEST = GroupedEventReadCriteria.new(
      event_types: [ "CandidateImpactSurfaceRegistered" ],
      direction: :desc
    )

    CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE = GroupedEventReadCriteria.new(
      event_types: [
        "CandidateImpactRegistrySweepStarted",
        "CandidateImpactRegistrySweepSkipped",
        "CandidateImpactRegistrySweepProgressed",
        "CandidateImpactRegistrySweepCompleted"
      ],
      direction: :desc
    )

    CANDIDATE_IMPACT_PAIR_SCAN_STATE = GroupedEventReadCriteria.new(
      event_types: [
        "CandidateImpactPairScanStarted",
        "CandidateImpactPairScanSkipped",
        "CandidateImpactPairScanProgressed",
        "CandidateImpactPairScanCompleted"
      ],
      direction: :desc
    )

    COORDINATION_TASK_HISTORY = EventReadCriteria.new(
      event_types: [
        "CoordinationTaskSubmitted",
        "CoordinationTaskExecutionStarted",
        "CoordinationTaskCompleted",
        "CoordinationTaskFailed",
        "CoordinationTaskCancellationRequested",
        "CoordinationTaskCancelled"
      ],
      maximum_count: 4,
      direction: :asc
    )

    CHANGE_SET_EXISTENCE = GroupedEventReadCriteria.new(
      event_types: [ "ChangeSetCreated" ],
      direction: :desc
    )

    WORK_ITEM_EXISTENCE = GroupedEventReadCriteria.new(
      event_types: [ "WorkItemCreated" ],
      direction: :desc
    )

    CHANGE_SET_FOR_WORK_ITEM_CREATION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "ChangeSetActivated"
      ],
      maximum_count: 102,
      direction: :asc
    )

    CHANGE_SET_FOR_DEPENDENCY_DECLARATION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared",
        "ChangeSetActivated"
      ],
      maximum_count: 602,
      direction: :asc
    )

    CHANGE_SET_FOR_ACTIVATION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "ChangeSetAcceptanceCriteriaDefined",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared",
        "ChangeSetActivated"
      ],
      maximum_count: 603,
      direction: :asc
    )

    CHANGE_SET_MEMBERS_FOR_READINESS = EventReadCriteria.new(
      event_types: [ "WorkItemAddedToChangeSet" ],
      maximum_count: 100,
      direction: :asc
    )

    CHANGE_SET_FOR_READINESS_EVALUATION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared",
        "WorkItemDependencySatisfied",
        "ChangeSetActivated"
      ],
      maximum_count: 1_102,
      direction: :asc
    )

    CHANGE_SET_FOR_DEPENDENCY_SATISFACTION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared",
        "WorkItemDependencySatisfied",
        "ChangeSetActivated"
      ],
      maximum_count: 1_102,
      direction: :asc
    )

    CHANGE_SET_FOR_COMPLETION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemDependencyDeclared",
        "WorkItemDependencySatisfied",
        "ChangeSetActivated",
        "ChangeSetCompleted"
      ],
      maximum_count: 1_103,
      direction: :asc
    )

    CHANGE_SET_FOR_MERGE_AUTHORIZATION = CHANGE_SET_FOR_COMPLETION

    WORK_ITEM_FOR_READINESS_EVALUATION = EventReadCriteria.new(
      event_types: [ "WorkItemCreated", "WorkItemMadeReady", "WorkItemAcquired", "WorkItemCompleted" ],
      maximum_count: 4,
      direction: :asc
    )

    WORK_ITEM_FOR_CHANGE_SET_COMPLETION = EventReadCriteria.new(
      event_types: [ "WorkItemCreated", "WorkItemCandidateSelected", "WorkItemCompleted" ],
      maximum_count: 3,
      direction: :asc
    )

    WORK_ITEM_FOR_MERGE_AUTHORIZATION = WORK_ITEM_FOR_CHANGE_SET_COMPLETION

    CHANGE_SET_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "ChangeSetActivated"
      ],
      maximum_count: 102,
      direction: :asc
    )

    WORK_ITEM_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [ "WorkItemCreated", "WorkItemMadeReady", "WorkItemAcquired" ],
      maximum_count: 3,
      direction: :asc
    )

    CHANGE_SET_FOR_WORK_ITEM_COMPLETION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "ChangeSetActivated",
        "ChangeSetCompleted"
      ],
      maximum_count: 103,
      direction: :asc
    )

    WORK_ITEM_FOR_COMPLETION = EventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemMadeReady",
        "WorkItemAcquired",
        "WorkItemCandidateSelected",
        "WorkItemCompleted"
      ],
      maximum_count: 5,
      direction: :asc
    )

    ATTEMPT_FOR_WORK_ITEM_COMPLETION = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptStarted",
        "WriteSetReserved",
        "WriteSetExpanded",
        "AttemptCompleted"
      ],
      maximum_count: 35,
      direction: :asc
    )

    ATTEMPT_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted" ],
      maximum_count: 2,
      direction: :asc
    )

    ATTEMPT_FOR_WRITE_SET_RESERVATION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved" ],
      maximum_count: 3,
      direction: :asc
    )

    ATTEMPT_FOR_WRITE_SET_EXPANSION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetExpanded" ],
      maximum_count: 34,
      direction: :asc
    )

    ATTEMPT_FOR_CANDIDATE_SUBMISSION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetExpanded" ],
      maximum_count: 34,
      direction: :asc
    )

    ATTEMPT_LATEST_WRITE_SET_LIFECYCLE = GroupedEventReadCriteria.new(
      event_types: [ "WriteSetRenewed", "WriteSetReleased" ],
      direction: :desc
    )

    RESOURCE_LEASE_FOR_RESERVATION = GroupedEventReadCriteria.new(
      event_types: [
        "ResourceLeaseAcquired",
        "ResourceLeaseRenewed",
        "ResourceLeaseReleased",
        "ResourceLeaseExpired"
      ],
      direction: :desc
    )

    RESOURCE_LEASE_FOR_CANDIDATE_SUBMISSION = GroupedEventReadCriteria.new(
      event_types: [
        "ResourceLeaseAcquired",
        "ResourceLeaseRenewed",
        "ResourceLeaseReleased",
        "ResourceLeaseExpired"
      ],
      direction: :desc
    )
  end
end
