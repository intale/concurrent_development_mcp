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
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_proposal(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationProposed" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_terminal(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted", "DecisionInterpretationRejected" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_slot_acceptance(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.interpretation_acceptance(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Interpretation",
        event_types: [ "DecisionInterpretationAccepted" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.decision_activation(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "HumanGuidance",
        stream_name: "Decision",
        event_types: [ "DecisionActivated" ],
        markers: [ marker ],
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

    RESOURCE_LEASE_LIFECYCLE_EVENT_TYPES = %w[
      ResourceLeaseAcquired
      ResourceLeaseRenewed
      ResourceLeaseReleased
      ResourceLeaseExpired
    ].freeze
    RESOURCE_BOUNDARY_DECISION_DELTA_MAXIMUM_COUNT = 256
    RESOURCE_BOUNDARY_ROLLOVER_SOFT_COUNT = 128
    RESOURCE_BOUNDARY_ROLLOVER_DELTA_MAXIMUM_COUNT = 4_096
    RESOURCE_BOUNDARY_ACTIVE_LEASE_MAXIMUM_COUNT = 1_024
    RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION = (2**63) - 1

    WORK_INTENTION_LIFECYCLE_EVENT_TYPES = %w[
      ResourceWorkIntentionDeclared
      ResourceWorkIntentionRenewed
      ResourceWorkIntentionWithdrawn
      ResourceWorkIntentionExpired
    ].freeze
    WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT = 4_096
    WORK_INTENTION_BOUNDARY_ROLLOVER_SOFT_COUNT = 2_048
    WORK_INTENTION_BOUNDARY_ROLLOVER_MAXIMUM_COUNT = 8_192

    def self.work_intention_boundary(markers)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceWorkIntention",
        event_types: WORK_INTENTION_LIFECYCLE_EVENT_TYPES,
        markers:,
        maximum_count: WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT,
        direction: :asc
      )
    end

    def self.work_intention_set_for_attempt(marker)
      GlobalMarkedEventReadCriteria.new(
        stream_context: "DevelopmentCoordination",
        stream_name: "WorkIntentionSet",
        event_types: [ "WorkIntentionSetCreated" ],
        markers: [ marker ],
        maximum_count: 1,
        direction: :asc
      )
    end

    def self.resource_lease_boundary_pages(marker, from_position:, to_position:, maximum_count:)
      RESOURCE_LEASE_LIFECYCLE_EVENT_TYPES.map do |event_type|
        GlobalMarkedEventPageCriteria.new(
          stream_context: "DevelopmentCoordination",
          stream_name: "ResourceLease",
          event_type:,
          markers: [ marker ],
          from_position:,
          to_position:,
          page_size: maximum_count,
          direction: :asc
        )
      end
    end

    COMMAND_REGISTRATION = EventReadCriteria.new(
      event_types: [ "CommandRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    COMMAND_HISTORY = EventReadCriteria.new(
      event_types: [ "CommandRegistered", "CommandSucceeded", "CommandRejected" ],
      maximum_count: 2,
      direction: :asc
    )

    REPOSITORY_REGISTRATION = EventReadCriteria.new(
      event_types: [ "RepositoryRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    SKILL_LATEST_REVISION = GroupedEventReadCriteria.new(
      event_types: [ "SkillRevisionPublished" ],
      direction: :desc
    )

    DEVELOPMENT_ARTIFACT_HISTORY = EventReadCriteria.new(
      event_types: [
        "DevelopmentArtifactCaptured",
        "DevelopmentArtifactRelationDeclared",
        "DevelopmentArtifactRelationSuperseded"
      ],
      maximum_count: Types::DEVELOPMENT_ARTIFACT_HISTORY_MAXIMUM_COUNT,
      direction: :asc
    )

    DEVELOPMENT_ARTIFACT_CAPTURE = EventReadCriteria.new(
      event_types: [ "DevelopmentArtifactCaptured" ],
      maximum_count: 1,
      direction: :asc
    )

    DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY = EventReadCriteria.new(
      event_types: [
        "DevelopmentArtifactObservationRecorded",
        "DevelopmentArtifactObservationFactLinked",
        "DevelopmentArtifactClassificationCorrectionRecorded",
        "DevelopmentArtifactObserved",
        "DevelopmentArtifactClassificationCorrected"
      ],
      maximum_count: Types::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY_MAXIMUM_COUNT,
      direction: :asc
    )

    OPERATION_BATCH_HISTORY = EventReadCriteria.new(
      event_types: [
        "OperationBatchCreated",
        "OperationBatchTargetSelected",
        "OperationBatchItemEnqueued",
        "OperationBatchItemSucceeded",
        "OperationBatchItemRejected",
        "OperationBatchItemCompletionLinked",
        "OperationBatchContinuationRequested",
        "OperationBatchCancellationRequested",
        "OperationBatchCancelled",
        "OperationBatchCompleted"
      ],
      maximum_count: Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS,
      direction: :asc
    )

    OPERATION_BATCH_EXISTENCE = EventReadCriteria.new(
      event_types: [ "OperationBatchCreated" ],
      maximum_count: 1,
      direction: :asc
    )

    DECISION_EXISTENCE = EventReadCriteria.new(
      event_types: [ "DecisionRecorded", "DecisionActivated" ],
      maximum_count: 3,
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

    DECISION_PARTITION_STATE = EventReadCriteria.new(
      event_types: [
        "DecisionPartitionAdvanced",
        "DecisionAddedToPartition",
        "DecisionRemovedFromPartition"
      ],
      maximum_count: 2_048,
      direction: :asc
    )

    DECISION_PARTITION_LATEST = GroupedEventReadCriteria.new(
      event_types: [
        "DecisionPartitionAdvanced",
        "DecisionAddedToPartition",
        "DecisionRemovedFromPartition"
      ],
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

    AGENT_CHOICE_IMPACT_SCAN_SOURCES = EventReadCriteria.new(
      event_types: [ "AgentChoiceImpactScanSourceLinked" ],
      maximum_count: 1,
      direction: :asc
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
      event_types: [ "AgentChoiceImpactAssessed", "AgentChoiceImpactAssessmentRecorded" ],
      maximum_count: 1,
      direction: :asc
    )

    ATTEMPT_FOR_AGENT_CHOICE = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted"
      ],
      maximum_count: 35,
      direction: :asc
    )

    CANDIDATE_EXISTENCE = EventReadCriteria.new(
      event_types: [ "CandidateCreated" ],
      maximum_count: 1,
      direction: :asc
    )

    CANDIDATE_HEAD_REGISTRATION = EventReadCriteria.new(
      event_types: [ "CandidateHeadRegistered" ],
      maximum_count: 1,
      direction: :asc
    )

    CANDIDATE_FOR_MERGE_SNAPSHOT = EventReadCriteria.new(
      event_types: Candidates::StateLoader::FACT_TYPES,
      maximum_count: 11,
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
      event_types: [ "MergeSnapshotVerificationAssigned" ],
      maximum_count: Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT + 1,
      direction: :asc
    )

    MERGE_SNAPSHOT_VERIFIED = EventReadCriteria.new(
      event_types: [ "MergeSnapshotVerificationSelected", "MergeSnapshotVerified" ],
      maximum_count: 2,
      direction: :asc
    )

    MERGE_VERIFICATION_SUBMISSION = EventReadCriteria.new(
      event_types: [ "MergeSnapshotVerificationSubmitted" ],
      maximum_count: 1,
      direction: :asc
    )

    MERGE_OBSERVATION = EventReadCriteria.new(
      event_types: [ "MergeObserved" ],
      maximum_count: 1,
      direction: :asc
    )

    RELEASE_SET_PREPARATION = EventReadCriteria.new(
      event_types: [ "ReleaseSetCreated", "ReleaseSetMemberAdded", "ReleaseSetPrepared" ],
      maximum_count: Types::RELEASE_SET_MAXIMUM_MEMBERS + 3,
      direction: :asc
    )

    RELEASE_SET_LIFECYCLE = EventReadCriteria.new(
      event_types: [
        "ReleaseSetCreated",
        "ReleaseSetMemberAdded",
        "ReleaseSetPrepared",
        "RepositoryIntegrationRecorded",
        "RepositoryIntegrationMergeLinked",
        "ReleaseSetVerificationRecorded",
        "ReleaseSetIntegrationLinked",
        "ReleaseSetActivated",
        "ReleaseSetCompensationRequested",
        "ReleaseSetSuccessfulIntegrationLinked",
        "RepositoryCompensationRecorded",
        "ReleaseSetOutcomeRecorded",
        "ReleaseSetCompleted"
      ],
      maximum_count: Types::RELEASE_SET_LIFECYCLE_MAXIMUM_EVENTS,
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
        "VerificationObligationAddedToChangeSet",
        "VerificationObligationSourceCandidateAssigned",
        "VerificationObligationTargetCandidateAssigned",
        "VerificationObligationClaimed",
        "VerificationEvidenceSubmitted",
        "VerificationObligationEvidenceSelected",
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
        "VerificationObligationAddedToChangeSet",
        "VerificationObligationSourceCandidateAssigned",
        "VerificationObligationTargetCandidateAssigned",
        "VerificationObligationClaimed",
        "VerificationEvidenceSubmitted",
        "VerificationObligationEvidenceSelected",
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

    VERIFICATION_OBLIGATION_VALIDITY_SCAN_SOURCES = EventReadCriteria.new(
      event_types: [ "VerificationObligationValidityScanSourceLinked" ],
      maximum_count: 1,
      direction: :asc
    )

    VERIFICATION_EVIDENCE_HISTORY = EventReadCriteria.new(
      event_types: [ "VerificationEvidenceSubmitted" ],
      maximum_count: Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT,
      direction: :asc
    )

    VERIFICATION_OBLIGATION_OUTCOME = EventReadCriteria.new(
      event_types: [
        "VerificationObligationCreated",
        "VerificationObligationAddedToChangeSet",
        "VerificationObligationSourceCandidateAssigned",
        "VerificationObligationTargetCandidateAssigned",
        "VerificationObligationClaimed",
        "VerificationEvidenceSubmitted",
        "VerificationObligationEvidenceSelected",
        "VerificationObligationSatisfied",
        "VerificationObligationFailed",
        "VerificationObligationWaived",
        "VerificationObligationInvalidated"
      ],
      maximum_count: 52,
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

    CANDIDATE_IMPACT_REGISTRY_SWEEP_SOURCES = EventReadCriteria.new(
      event_types: [ "CandidateImpactRegistrySweepSourceLinked" ],
      maximum_count: 2,
      direction: :asc
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

    CANDIDATE_IMPACT_PAIR_SCAN_SOURCES = EventReadCriteria.new(
      event_types: [ "CandidateImpactPairScanSourceLinked" ],
      maximum_count: 3,
      direction: :asc
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
      maximum_count: 8,
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

    WORK_ITEM_FOR_READINESS_EVALUATION = GroupedEventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemGoalDefined",
        "WorkItemAcceptanceCriteriaDefined",
        "WorkItemCompetitiveModeSelected",
        "WorkItemMadeReady",
        "WorkItemAcquired",
        "WorkItemRequeued",
        "WorkItemCandidateSelected",
        "WorkItemCompleted"
      ],
      direction: :desc
    )

    WORK_ITEM_FOR_CHANGE_SET_COMPLETION = EventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemCandidateSelected",
        "WorkItemCompleted"
      ],
      maximum_count: 5,
      direction: :asc
    )

    WORK_ITEM_LATEST_CANDIDATE_SELECTION = EventReadCriteria.new(
      event_types: [ "WorkItemCandidateSelected" ],
      maximum_count: 1,
      direction: :desc
    )

    CHANGE_SET_DEFINITION_FOR_PROJECTION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "ChangeSetGoalDefined",
        "ChangeSetAcceptanceCriteriaDefined"
      ],
      maximum_count: 3,
      direction: :asc
    )

    WORK_ITEM_DEFINITION_FOR_PROJECTION = EventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemGoalDefined",
        "WorkItemAcceptanceCriteriaDefined",
        "WorkItemCompetitiveModeSelected"
      ],
      maximum_count: 6,
      direction: :asc
    )

    ATTEMPT_DEFINITION_FOR_PROJECTION = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted"
      ],
      maximum_count: 5,
      direction: :asc
    )

    WORK_ITEM_COMPLETION_FOR_PROJECTION = EventReadCriteria.new(
      event_types: [
        "WorkItemCandidateSelected",
        "WorkItemOutputRecorded",
        "WorkItemCompleted"
      ],
      maximum_count: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT + 2,
      direction: :asc
    )

    WORK_ITEM_FOR_MERGE_AUTHORIZATION = EventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemDependencySatisfied",
        "WorkItemCandidateSelected",
        "WorkItemCompleted"
      ],
      maximum_count: 505,
      direction: :asc
    )

    CHANGE_SET_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [
        "ChangeSetCreated",
        "WorkItemAddedToChangeSet",
        "ChangeSetActivated"
      ],
      maximum_count: 102,
      direction: :asc
    )

    WORK_ITEM_FOR_ACQUISITION = GroupedEventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemGoalDefined",
        "WorkItemAcceptanceCriteriaDefined",
        "WorkItemCompetitiveModeSelected",
        "WorkItemMadeReady",
        "WorkItemAcquired",
        "WorkItemRequeued",
        "WorkItemCompleted"
      ],
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

    WORK_ITEM_FOR_COMPLETION = GroupedEventReadCriteria.new(
      event_types: [
        "WorkItemCreated",
        "WorkItemAddedToChangeSet",
        "WorkItemAssignedToRepository",
        "WorkItemGoalDefined",
        "WorkItemAcceptanceCriteriaDefined",
        "WorkItemCompetitiveModeSelected",
        "WorkItemMadeReady",
        "WorkItemAcquired",
        "WorkItemRequeued",
        "WorkItemCandidateSelected",
        "WorkItemOutputRecorded",
        "WorkItemCompleted"
      ],
      direction: :desc
    )

    ATTEMPT_FOR_WORK_ITEM_COMPLETION = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted",
        "WorkIntentionSetCreated",
        "WorkIntentionAddedToSet",
        "WriteSetReserved",
        "WriteSetExpanded",
        "AttemptCompleted"
      ],
      maximum_count: 137,
      direction: :asc
    )

    ATTEMPT_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted"
      ],
      maximum_count: 104,
      direction: :asc
    )

    ATTEMPT_FOR_WRITE_SET_RESERVATION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved" ],
      maximum_count: 3,
      direction: :asc
    )

    ATTEMPT_FOR_WORK_INTENTIONS = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted",
        "AttemptAbandoned",
        "AttemptCompleted"
      ],
      maximum_count: 9,
      direction: :asc
    )

    WORK_INTENTION_SET_STATE = EventReadCriteria.new(
      event_types: [ "WorkIntentionSetCreated", "WorkIntentionAddedToSet" ],
      maximum_count: 33,
      direction: :asc
    )

    WORK_INTENTION_STATE = GroupedEventReadCriteria.new(
      event_types: WORK_INTENTION_LIFECYCLE_EVENT_TYPES,
      direction: :desc
    )

    ATTEMPT_FOR_WRITE_SET_EXPANSION = EventReadCriteria.new(
      event_types: [ "AttemptAuthorized", "AttemptStarted", "WriteSetReserved", "WriteSetExpanded" ],
      maximum_count: 34,
      direction: :asc
    )

    ATTEMPT_FOR_CANDIDATE_SUBMISSION = EventReadCriteria.new(
      event_types: [
        "AttemptAuthorized",
        "AttemptAssignedToWorkItem",
        "AttemptAssignedToAgent",
        "AttemptBaseSnapshotRecorded",
        "AttemptStarted",
        "WriteSetReserved",
        "WriteSetExpanded"
      ],
      maximum_count: 37,
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
