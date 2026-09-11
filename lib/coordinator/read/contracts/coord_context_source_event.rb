# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CoordContextSourceEvent < Dry::Validation::Contract
      EVENT_STREAMS = {
        [ "ChangeSetCreated", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetCreated", 2 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetGoalDefined", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetAcceptanceCriteriaDefined", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetAcceptanceCriteriaDefined", 2 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemAddedToChangeSet", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemAddedToChangeSet", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemDependencyDeclared", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemDependencyDeclared", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "ChangeSetActivated", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetActivated", 2 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemDependencySatisfied", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemDependencySatisfied", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "ChangeSetCompleted", 1 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "ChangeSetCompleted", 2 ] => [ "DevelopmentPlanning", "ChangeSet" ],
        [ "WorkItemCreated", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCreated", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemAssignedToRepository", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemGoalDefined", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemAcceptanceCriteriaDefined", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCompetitiveModeSelected", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemMadeReady", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemMadeReady", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemAcquired", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemAcquired", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCandidateSelected", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCandidateSelected", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemOutputRecorded", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCompleted", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemCompleted", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemRequeued", 1 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "WorkItemRequeued", 2 ] => [ "DevelopmentExecution", "WorkItem" ],
        [ "AttemptAuthorized", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptAuthorized", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptAssignedToWorkItem", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptAssignedToAgent", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptBaseSnapshotRecorded", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptStarted", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptStarted", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptAbandoned", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptAbandoned", 3 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "WriteSetReserved", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "WriteSetExpanded", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "WriteSetRenewed", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "WriteSetReleased", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptCompleted", 1 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "AttemptCompleted", 2 ] => [ "DevelopmentExecution", "Attempt" ],
        [ "CandidateSubmitted", 3 ] => [ "DevelopmentIntegration", "Candidate" ],
        [ "ResourceWorkIntentionDeclared", 1 ] => [ "DevelopmentCoordination", "ResourceWorkIntention" ],
        [ "ResourceWorkIntentionRenewed", 1 ] => [ "DevelopmentCoordination", "ResourceWorkIntention" ],
        [ "ResourceWorkIntentionWithdrawn", 1 ] => [ "DevelopmentCoordination", "ResourceWorkIntention" ],
        [ "ResourceWorkIntentionExpired", 1 ] => [ "DevelopmentCoordination", "ResourceWorkIntention" ]
      }.freeze
      EVENT_TYPES = EVENT_STREAMS.keys.map(&:first).uniq.freeze
      SCHEMA_VERSIONS = EVENT_STREAMS.keys.map(&:last).uniq.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_TYPES)
        required(:schema_version).filled(:integer, included_in?: SCHEMA_VERSIONS)
        required(:stream_context).filled(:string)
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
      end

      rule(:event_type, :schema_version, :stream_context, :stream_name) do
        expected = EVENT_STREAMS[[ values[:event_type], values[:schema_version] ]]
        unless expected
          key(:schema_version).failure("must match the projected event schema")
          next
        end
        next if expected == [ values[:stream_context], values[:stream_name] ]

        key(:event_type).failure("does not belong to the supplied source stream")
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
