# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class CheckpointWriter
    POLICY_VERSION = "checkpoint-statistics/v1"

    def initialize(event_store:, event_factory: Coordinator::Write::EventFactory.new, markers: CheckpointMarkers.new)
      @event_store, @event_factory, @markers = event_store, event_factory, markers
    end

    def call(plan:, command_id:, actor:, change_set_id:, repository_id:, event_ids:,
      caused_by:, correlation_id:, expected_revision: nil)
      events = plan.events.zip(event_ids).map do |event, event_id|
        markers = @markers.call(command_id:, change_set_id:, repository_id:)
        case event.class.event_type
        when "ChangeSetRepositoryCheckpointStatisticsAssigned"
          markers << @markers.owner(change_set_id:, repository_id:)
        when "CandidateCheckpointCounted"
          markers << @markers.candidate(event.candidate_id)
        end
        @event_factory.build!(event:, event_id:, markers:, caused_by:, correlation_id:,
          metadata: Coordinator::Write::EventMetadata.new(command_id:, actor_kind: actor.kind, actor_id: actor.id,
            recorded_by: "coordinator", policy_version: POLICY_VERSION))
      end
      stream = plan.writes.first.stream
      if expected_revision.nil?
        @event_store.append(stream, events)
      else
        @event_store.append(stream, events, expected_revision:)
      end
    end
  end
end
