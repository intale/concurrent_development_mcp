# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class CoordContextSourceEvent < Dry::Validation::Contract
      EVENT_STREAMS = {
        "ChangeSetCreated" => [ "DevelopmentPlanning", "ChangeSet" ],
        "ChangeSetAcceptanceCriteriaDefined" => [ "DevelopmentPlanning", "ChangeSet" ],
        "WorkItemAddedToChangeSet" => [ "DevelopmentPlanning", "ChangeSet" ],
        "WorkItemDependencyDeclared" => [ "DevelopmentPlanning", "ChangeSet" ],
        "ChangeSetActivated" => [ "DevelopmentPlanning", "ChangeSet" ],
        "WorkItemCreated" => [ "DevelopmentExecution", "WorkItem" ],
        "WorkItemMadeReady" => [ "DevelopmentExecution", "WorkItem" ],
        "WorkItemAcquired" => [ "DevelopmentExecution", "WorkItem" ],
        "AttemptAuthorized" => [ "DevelopmentExecution", "Attempt" ],
        "AttemptStarted" => [ "DevelopmentExecution", "Attempt" ]
      }.freeze

      config.validate_keys = true

      params do
        required(:event_type).filled(:string, included_in?: EVENT_STREAMS.keys)
        required(:schema_version).filled(:integer, eql?: 1)
        required(:stream_context).filled(:string)
        required(:stream_name).filled(:string)
        required(:stream_id).filled(:string)
        required(:stream_revision).filled(:integer, gteq?: 0)
      end

      rule(:event_type, :stream_context, :stream_name) do
        expected = EVENT_STREAMS[values[:event_type]]
        next unless expected
        next if expected == [ values[:stream_context], values[:stream_name] ]

        key(:event_type).failure("does not belong to the supplied source stream")
      end

      rule(:stream_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
