# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class CheckpointsLoader
    CANDIDATE_TYPES = %w[CandidateSubmitted CandidateAssignedToAttempt CandidateAssignedToRepository].freeze
    ATTEMPT_TYPES = %w[AttemptAuthorized AttemptAssignedToWorkItem AttemptBaseSnapshotRecorded].freeze
    WORK_ITEM_TYPES = %w[WorkItemCreated WorkItemAddedToChangeSet WorkItemAssignedToRepository].freeze

    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new, markers: CheckpointMarkers.new)
      @event_store, @stream_factory, @markers = event_store, stream_factory, markers
    end

    def selector(change_set_id:, repository_id:)
      Coordinator::Write::NaturalKeys::Registry::SelectorV1.new(
        stream_context: "DevelopmentIntegration", stream_name: "CheckpointStatistics",
        event_type: "ChangeSetRepositoryCheckpointStatisticsAssigned",
        marker: @markers.owner(change_set_id:, repository_id:))
    end

    def state(statistics_id)
      events = @event_store.read_grouped(@stream_factory.checkpoint_statistics(statistics_id),
        Coordinator::Write::EventQueries::CHECKPOINT_STATISTICS_CONTROL)
      assignment = events.find { _1.type == "ChangeSetRepositoryCheckpointStatisticsAssigned" }
      number = events.find { _1.type == "ChangeSetRepositoryCheckpointNumberChanged" }
      CheckpointStateV1.new(statistics_id:,
        change_set_id: assignment&.data&.fetch("change_set_id"),
        repository_id: assignment&.data&.fetch("repository_id"),
        checkpoints_number: number&.data&.fetch("checkpoints_number"),
        latest_revision: events.first&.stream_revision || -1)
    end

    def source_scope(reference)
      return unless reference.type == "CandidateSubmitted" &&
                    reference.stream_context == "DevelopmentIntegration" && reference.stream_name == "Candidate"

      events = identities(@stream_factory.candidate(reference.stream_id), CANDIDATE_TYPES)
      submitted = events.find { _1.type == "CandidateSubmitted" }
      assignment = events.find { _1.type == "CandidateAssignedToAttempt" }
      repository = events.find { _1.type == "CandidateAssignedToRepository" }
      return unless submitted && assignment && repository &&
                    submitted.id == reference.event_id && submitted.stream_revision == reference.stream_revision &&
                    submitted.metadata.fetch("schema_version") == 3 &&
                    events.all? { _1.data.fetch("candidate_id") == reference.stream_id }

      scope = CandidateCheckpointScopeV1.new(
        candidate_id: reference.stream_id, change_set_id: assignment.data.fetch("change_set_id"),
        work_item_id: assignment.data.fetch("work_item_id"), attempt_id: assignment.data.fetch("attempt_id"),
        repository_id: repository.data.fetch("repository_id"))
      return unless attempt_matches?(scope) && work_item_matches?(scope)

      scope
    end

    def counted?(statistics_id, candidate_id)
      @event_store.read_marked(@stream_factory.checkpoint_statistics(statistics_id),
        Coordinator::Write::MarkedEventReadCriteria.new(event_type: "CandidateCheckpointCounted",
          marker: @markers.candidate(candidate_id), maximum_count: 1, direction: :asc)).any?
    end

    def owner_exists?(stream, event_type)
      @event_store.read(stream, Coordinator::Write::EventReadCriteria.new(
        event_types: [ event_type ], maximum_count: 1, direction: :asc)).any?
    end

    private

    def identities(stream, event_types)
      @event_store.read(stream, Coordinator::Write::EventReadCriteria.new(
        event_types:, maximum_count: 3, direction: :asc))
    end

    def attempt_matches?(scope)
      events = identities(@stream_factory.attempt(scope.attempt_id), ATTEMPT_TYPES)
      authorization = events.find { _1.type == "AttemptAuthorized" }
      assignment = events.find { _1.type == "AttemptAssignedToWorkItem" }
      base = events.find { _1.type == "AttemptBaseSnapshotRecorded" }
      return false unless authorization && assignment && base

      events.all? { _1.data.fetch("attempt_id") == scope.attempt_id } &&
        assignment.data.fetch("change_set_id") == scope.change_set_id &&
        assignment.data.fetch("work_item_id") == scope.work_item_id &&
        base.data.fetch("repository_id") == scope.repository_id
    end

    def work_item_matches?(scope)
      events = identities(@stream_factory.work_item(scope.work_item_id), WORK_ITEM_TYPES)
      created = events.find { _1.type == "WorkItemCreated" }
      assignment = events.find { _1.type == "WorkItemAddedToChangeSet" }
      repository = events.find { _1.type == "WorkItemAssignedToRepository" }
      return false unless created && assignment && repository

      events.all? { _1.data.fetch("work_item_id") == scope.work_item_id } &&
        assignment.data.fetch("change_set_id") == scope.change_set_id &&
        repository.data.fetch("repository_id") == scope.repository_id
    end
  end
end
