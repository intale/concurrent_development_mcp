# frozen_string_literal: true

module Coordinator::Processes::ProcessManagers
  class CheckpointStatistics
    RULE_VERSION = "checkpoint-statistics/v1"
    ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "checkpoint-statistics")

    def initialize(event_store:, planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
      loader: Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:),
      ensure_statistics: Coordinator::Write::Operations::ExecuteEnsureChangeSetRepositoryCheckpointStatistics.new(event_store:),
      count: Coordinator::Write::Operations::ExecuteCountCandidateCheckpoint.new(event_store:))
      @planner, @loader, @ensure_statistics, @count = planner, loader, ensure_statistics, count
    end

    def call(event)
      reference = Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
        stream_context: event.stream.context, stream_name: event.stream.stream_name,
        stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
      allocation = plan(event, "ensure", event.stream.stream_id, allocate_target_entity: true)
      scope = @loader.source_scope(reference)
      unless scope
        @planner.record_dispatch_failure(process_step: allocation,
          failure: Coordinator::Write::OutcomeError.new(code: :projection_statistics_source_mismatch,
            message: "Candidate's immutable checkpoint ownership is inconsistent", details: { candidate_id: event.stream.stream_id }))
        return nil
      end

      ensured = @ensure_statistics.call_command(
        Coordinator::Write::Commands::EnsureChangeSetRepositoryCheckpointStatistics.new(
          command_id: allocation.target_command_id, actor: ACTOR,
          statistics_id: allocation.target_entity_id!, change_set_id: scope.change_set_id,
          repository_id: scope.repository_id), caused_by: allocation.event)
      if ensured.failure?
        @planner.record_dispatch_failure(process_step: allocation, failure: ensured.failure)
        return nil
      end

      statistics_id = ensured.value!
      step = plan(event, "count", statistics_id)
      result = @count.call_command(Coordinator::Write::Commands::CountCandidateCheckpoint.new(
        command_id: step.target_command_id, actor: ACTOR, statistics_id:, source_event: reference), caused_by: step.event)
      @planner.record_dispatch_failure(process_step: step, failure: result.failure) if result.failure?
      nil
    end

    private

    def plan(event, step_name, subject_id, allocate_target_entity: false)
      @planner.call(source_event: event, process_name: "checkpoint-statistics", step_name:,
        subject_kind: "checkpoint-statistics", subject_id:, rule_version: RULE_VERSION, allocate_target_entity:)
    end
  end
end
