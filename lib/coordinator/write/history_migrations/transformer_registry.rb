# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TransformerRegistry
      include Dry::Monads[:result]

      def initialize(
        schema_registry: EventSchemaRegistry.new,
        repository_registered_v1:,
        guidance_message_v1:,
        change_set_v1:,
        work_item_v1:,
        attempt_v1:,
        candidate_submission_v1:,
        candidate_evidence_v1:,
        candidate_head_v1:,
        candidate_impact_v1:,
        coordination_task_submitted_v2:,
        coordination_task_lifecycle:,
        command_completed_v1:
      )
        @schema_registry = schema_registry
        @definitions = {
          [ "RepositoryRegistered", 1 ] => repository_registered_v1,
          [ "UserUtteranceRecorded", 1 ] => guidance_message_v1,
          [ "UserUtteranceForwardedByAgent", 1 ] => guidance_message_v1,
          [ "ChangeSetCreated", 1 ] => change_set_v1,
          [ "ChangeSetAcceptanceCriteriaDefined", 1 ] => change_set_v1,
          [ "ChangeSetActivated", 1 ] => change_set_v1,
          [ "ChangeSetCompleted", 1 ] => change_set_v1,
          [ "WorkItemCreated", 1 ] => work_item_v1,
          [ "WorkItemAddedToChangeSet", 1 ] => work_item_v1,
          [ "WorkItemDependencyDeclared", 1 ] => work_item_v1,
          [ "WorkItemDependencySatisfied", 1 ] => work_item_v1,
          [ "WorkItemMadeReady", 1 ] => work_item_v1,
          [ "WorkItemAcquired", 1 ] => work_item_v1,
          [ "WorkItemRequeued", 1 ] => work_item_v1,
          [ "WorkItemCandidateSelected", 1 ] => work_item_v1,
          [ "WorkItemCompleted", 1 ] => work_item_v1,
          [ "AttemptAuthorized", 1 ] => attempt_v1,
          [ "AttemptStarted", 1 ] => attempt_v1,
          [ "AttemptCompleted", 1 ] => attempt_v1,
          [ "AttemptAbandoned", 2 ] => attempt_v1,
          [ "CandidateSubmitted", 2 ] => candidate_submission_v1,
          [ "CandidateChangeManifestCaptured", 1 ] => candidate_evidence_v1,
          [ "CandidateBuildContextCaptured", 1 ] => candidate_evidence_v1,
          [ "CandidateHeadRegistered", 1 ] => candidate_head_v1,
          [ "CandidateAttachedToAttempt", 1 ] => candidate_submission_v1,
          [ "CandidateImpactSurfaceDerived", 1 ] => candidate_impact_v1,
          [ "CandidateImpactSurfaceRegistered", 1 ] => candidate_impact_v1,
          [ "CoordinationTaskSubmitted", 2 ] => coordination_task_submitted_v2,
          [ "CoordinationTaskExecutionStarted", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancellationRequested", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancelled", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCompleted", 2 ] => coordination_task_lifecycle,
          [ "CoordinationTaskFailed", 1 ] => coordination_task_lifecycle,
          [ "CommandCompleted", 1 ] => command_completed_v1
        }.freeze
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:)
        schema_version = Integer(source_event.metadata.fetch("schema_version"))
        transformer = @definitions[[ source_event.type, schema_version ]]
        return Failure(unsupported(source_event, schema_version:)) unless transformer

        payload = @schema_registry.load(
          type: source_event.type,
          schema_version:,
          data: source_event.data
        )
        transformer.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload: payload
        )
      rescue KeyError, ArgumentError, TypeError => error
        Failure(invalid(source_event, error:, schema_version: defined?(schema_version) ? schema_version : nil))
      end

      private

      def unsupported(source_event, schema_version:)
        TransformationErrorV1.new(
          code: :unsupported_source_contract,
          message: "No historical transformation is registered for #{source_event.type}@#{schema_version}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end

      def invalid(source_event, error:, schema_version:)
        TransformationErrorV1.new(
          code: :invalid_source_event,
          message: "Historical source event is invalid: #{error.message}",
          event_type: source_event.type,
          schema_version:,
          source_event_id: source_event.id
        )
      end
    end
  end
end
