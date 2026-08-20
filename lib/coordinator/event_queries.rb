# frozen_string_literal: true

module Coordinator
  module EventQueries
    COMMAND_COMPLETION = EventReadCriteria.new(
      event_types: [ "CommandCompleted" ],
      maximum_count: 1,
      direction: :desc
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
  end
end
