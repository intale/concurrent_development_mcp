# frozen_string_literal: true

module Coordinator::Processes::ProcessManagers
  class ArtifactRelationStatistics
    class Rejected < StandardError; end

    RULE_VERSION = "artifact-relation-statistics/v1"
    ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "artifact-relation-statistics")

    def initialize(event_store:,
      planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
      ensure_statistics: Coordinator::Write::Operations::ExecuteEnsureDevelopmentArtifactRelationStatistics.new(event_store:),
      reconcile: Coordinator::Write::Operations::ExecuteReconcileDevelopmentArtifactRelationsNumber.new(event_store:),
      record_failure: Coordinator::Write::Operations::ExecuteRecordDevelopmentArtifactRelationsReconciliationFailure.new(event_store:),
      retryability: Coordinator::Write::Tasks::CommandRejectionRetryability.new)
      @planner, @ensure_statistics, @reconcile = planner, ensure_statistics, reconcile
      @record_failure, @retryability = record_failure, retryability
    end

    def call(event)
      artifact_id = event.data.fetch("source_artifact_id")
      allocation = plan(event, "ensure", artifact_id, allocate_target_entity: true)
      ensured = @ensure_statistics.call_command(
        Coordinator::Write::Commands::EnsureDevelopmentArtifactRelationStatistics.new(
          command_id: allocation.target_command_id, actor: ACTOR,
          artifact_id:, statistics_id: allocation.target_entity_id!), caused_by: allocation.event)
      if ensured.failure?
        @planner.record_dispatch_failure(process_step: allocation, failure: ensured.failure)
        return nil
      end

      statistics_id = ensured.value!
      step = plan(event, "reconcile", statistics_id)
      reference = Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
        stream_context: event.stream.context, stream_name: event.stream.stream_name,
        stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
      result = @reconcile.call_command(
        Coordinator::Write::Commands::ReconcileDevelopmentArtifactRelationsNumber.new(
          command_id: step.target_command_id, actor: ACTOR, statistics_id:, source_event: reference), caused_by: step.event)
      return nil if result.success?

      failed = result.failure
      failure_step = plan(event, "record-reconciliation-failure", statistics_id)
      recorded = @record_failure.call_command(
        Coordinator::Write::Commands::RecordDevelopmentArtifactRelationsReconciliationFailure.new(
          command_id: failure_step.target_command_id, actor: ACTOR, statistics_id:, source_event: reference,
          failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(
            failed_step: "reconcile-artifact-relations", reason_code: failed.code.to_s,
            reason: failed.message, retryable: @retryability.call(failed), effects_committed: false,
            attempts: failed.code == :concurrency_conflict ? 3 : 1)), caused_by: failure_step.event)
      unless recorded.success?
        @planner.record_dispatch_failure(process_step: failure_step, failure: recorded.failure)
        raise Rejected, "Artifact relation failure evidence could not be recorded: #{recorded.failure.message}"
      end
      @planner.record_dispatch_failure(process_step: step, failure: failed)
      nil
    end

    private

    def plan(event, step_name, subject_id, allocate_target_entity: false)
      @planner.call(source_event: event, process_name: "artifact-relation-statistics", step_name:,
        subject_kind: "artifact-relation-statistics", subject_id:, rule_version: RULE_VERSION, allocate_target_entity:)
    end
  end
end
