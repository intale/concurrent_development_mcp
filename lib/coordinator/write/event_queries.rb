# frozen_string_literal: true

module Coordinator::Write
  module EventQueries
    COMMAND_COMPLETION = EventReadCriteria.new(
      event_types: [ "CommandCompleted" ],
      maximum_count: 1,
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
        "ChangeSetActivated"
      ],
      maximum_count: 602,
      direction: :asc
    )

    WORK_ITEM_FOR_READINESS_EVALUATION = EventReadCriteria.new(
      event_types: [ "WorkItemCreated", "WorkItemMadeReady" ],
      maximum_count: 2,
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

    WORK_ITEM_FOR_ACQUISITION = EventReadCriteria.new(
      event_types: [ "WorkItemCreated", "WorkItemMadeReady", "WorkItemAcquired" ],
      maximum_count: 3,
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

    ATTEMPT_LATEST_WRITE_SET_RENEWAL = GroupedEventReadCriteria.new(
      event_types: [ "WriteSetRenewed" ],
      direction: :desc
    )

    RESOURCE_LEASE_FOR_RESERVATION = GroupedEventReadCriteria.new(
      event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed" ],
      direction: :desc
    )
  end
end
