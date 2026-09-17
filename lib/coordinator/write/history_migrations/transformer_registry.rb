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
        candidate_impact_scan_v1:,
        interpretation_lifecycle_v1:,
        decision_lifecycle_v1:,
        decision_relation_v1:,
        agent_choice_v1:,
        agent_choice_impact_v1:,
        agent_choice_impact_scan_v1:,
        coordination_task_submitted_v2:,
        coordination_task_lifecycle:,
        command_completed_v1:,
        development_artifact_v1:,
        development_artifact_relation_v1:,
        skill_revision_published_v2:,
        merge_snapshot_v1:,
        merge_snapshot_verification_v1:,
        merge_authorization_v1:,
        merge_observation_v1:
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
          [ "CandidateImpactPairScanStarted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanProgressed", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanSkipped", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactPairScanCompleted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepStarted", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepProgressed", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepSkipped", 1 ] => candidate_impact_scan_v1,
          [ "CandidateImpactRegistrySweepCompleted", 1 ] => candidate_impact_scan_v1,
          [ "DecisionInterpretationProposed", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionClarificationRequired", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionInterpretationAccepted", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionInterpretationRejected", 1 ] => interpretation_lifecycle_v1,
          [ "DecisionRecorded", 1 ] => decision_lifecycle_v1,
          [ "DecisionActivated", 1 ] => decision_lifecycle_v1,
          [ "DecisionDefinitionCorrected", 1 ] => decision_lifecycle_v1,
          [ "DecisionSlotOpened", 1 ] => decision_relation_v1,
          [ "DecisionSlotHeadChanged", 1 ] => decision_relation_v1,
          [ "DecisionPartitionAdvanced", 1 ] => decision_relation_v1,
          [ "AgentChoiceRecorded", 1 ] => agent_choice_v1,
          [ "AgentChoiceAccepted", 1 ] => agent_choice_v1,
          [ "AgentChoiceImpactAssessed", 1 ] => agent_choice_impact_v1,
          [ "AgentChoiceInvalidatedByDecision", 1 ] => agent_choice_impact_v1,
          [ "AgentChoiceImpactScanStarted", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanSkipped", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanProgressed", 1 ] => agent_choice_impact_scan_v1,
          [ "AgentChoiceImpactScanCompleted", 1 ] => agent_choice_impact_scan_v1,
          [ "CoordinationTaskSubmitted", 2 ] => coordination_task_submitted_v2,
          [ "CoordinationTaskExecutionStarted", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancellationRequested", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCancelled", 1 ] => coordination_task_lifecycle,
          [ "CoordinationTaskCompleted", 2 ] => coordination_task_lifecycle,
          [ "CoordinationTaskFailed", 1 ] => coordination_task_lifecycle,
          [ "CommandCompleted", 1 ] => command_completed_v1,
          [ "DevelopmentArtifactCaptured", 2 ] => development_artifact_v1,
          [ "DevelopmentArtifactObserved", 1 ] => development_artifact_v1,
          [ "DevelopmentArtifactClassificationCorrected", 1 ] => development_artifact_v1,
          [ "DevelopmentArtifactRelationDeclared", 1 ] => development_artifact_relation_v1,
          [ "DevelopmentArtifactRelationSuperseded", 1 ] => development_artifact_relation_v1,
          [ "SkillRevisionPublished", 2 ] => skill_revision_published_v2,
          [ "MergeSnapshotRegistered", 1 ] => merge_snapshot_v1,
          [ "MergeSnapshotCommitRegistered", 1 ] => merge_snapshot_v1,
          [ "MergeSnapshotVerificationSubmitted", 1 ] => merge_snapshot_verification_v1,
          [ "MergeSnapshotVerified", 1 ] => merge_snapshot_verification_v1,
          [ "MergeAuthorizationGranted", 1 ] => merge_authorization_v1,
          [ "MergeAuthorizationDenied", 1 ] => merge_authorization_v1,
          [ "MergeObserved", 1 ] => merge_observation_v1
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
