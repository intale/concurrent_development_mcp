# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetExecutor
      def initialize(
        event_store:,
        remove_resource: Operations::ExecuteRemoveResource.new(event_store:),
        create_change_set: Operations::ExecuteCreateChangeSet.new(event_store:),
        create_work_item: Operations::ExecuteCreateWorkItem.new(event_store:),
        declare_work_item_dependency: Operations::ExecuteDeclareWorkItemDependency.new(event_store:),
        activate_change_set: Operations::ExecuteActivateChangeSet.new(event_store:),
        acquire_work_item: Operations::ExecuteAcquireWorkItem.new(event_store:),
        complete_work_item: Operations::ExecuteCompleteWorkItem.new(event_store:),
        reserve_write_set: Operations::ExecuteReserveWriteSet.new(event_store:),
        expand_write_set: Operations::ExecuteExpandWriteSet.new(event_store:),
        renew_lease_set: Operations::ExecuteRenewLeaseSet.new(event_store:),
        release_lease_set: Operations::ExecuteReleaseLeaseSet.new(event_store:),
        record_guidance: Operations::ExecuteRecordGuidance.new(event_store:),
        propose_decision_interpretation: Operations::ExecuteProposeDecisionInterpretation.new(event_store:),
        adjudicate_decision_interpretation: Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:),
        activate_decision: Operations::ExecuteActivateDecision.new(event_store:),
        correct_decision: Operations::ExecuteCorrectDecision.new(event_store:),
        record_agent_choice: Operations::ExecuteRecordAgentChoice.new(event_store:),
        submit_candidate: Operations::ExecuteSubmitCandidate.new(event_store:),
        submit_candidate_impact_surface:
          Operations::ExecuteSubmitCandidateImpactSurface.new(event_store:),
        claim_verification_obligation:
          Operations::ExecuteClaimVerificationObligation.new(event_store:),
        submit_compatibility_assessment:
          Operations::ExecuteSubmitCompatibilityAssessment.new(event_store:),
        waive_verification_obligation:
          Operations::ExecuteWaiveVerificationObligation.new(event_store:),
        register_merge_snapshot:
          Operations::ExecuteRegisterMergeSnapshot.new(event_store:),
        submit_merge_snapshot_verification:
          Operations::ExecuteSubmitMergeSnapshotVerification.new(event_store:),
        request_merge_authorization:
          Operations::ExecuteRequestMergeAuthorization.new(event_store:),
        record_merge_observation:
          Operations::ExecuteRecordMergeObservation.new(event_store:),
        prepare_release_set:
          Operations::ExecutePrepareReleaseSet.new(event_store:),
        record_repository_integration:
          Operations::ExecuteRecordRepositoryIntegration.new(event_store:),
        record_release_set_verification:
          Operations::ExecuteRecordReleaseSetVerification.new(event_store:),
        record_release_set_activation:
          Operations::ExecuteRecordReleaseSetActivation.new(event_store:),
        complete_compensated_release_set:
          Operations::ExecuteCompleteCompensatedReleaseSet.new(event_store:),
        publish_skill_revision:
          Operations::ExecutePublishSkillRevision.new(event_store:),
        capture_development_artifact:
          Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:),
        correct_development_artifact_classification:
          Operations::ExecuteCorrectDevelopmentArtifactClassification.new(event_store:),
        declare_development_artifact_relation:
          Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:),
        operation_batch_command:
          Operations::ExecuteOperationBatchCommand.new(event_store:)
      )
        @register_repository = Operations::ExecuteRegisterRepository.new(event_store:)
        @resolve_resource = Operations::ExecuteResolveResource.new(event_store:)
        @remove_resource = remove_resource
        @create_change_set = create_change_set
        @create_work_item = create_work_item
        @declare_work_item_dependency = declare_work_item_dependency
        @activate_change_set = activate_change_set
        @acquire_work_item = acquire_work_item
        @complete_work_item = complete_work_item
        @abandon_attempt = Operations::ExecuteAbandonAttempt.new(event_store:)
        @reserve_write_set = reserve_write_set
        @expand_write_set = expand_write_set
        @renew_lease_set = renew_lease_set
        @release_lease_set = release_lease_set
        @record_guidance = record_guidance
        @propose_decision_interpretation = propose_decision_interpretation
        @adjudicate_decision_interpretation = adjudicate_decision_interpretation
        @activate_decision = activate_decision
        @correct_decision = correct_decision
        @record_agent_choice = record_agent_choice
        @submit_candidate = submit_candidate
        @submit_candidate_impact_surface = submit_candidate_impact_surface
        @claim_verification_obligation = claim_verification_obligation
        @submit_compatibility_assessment = submit_compatibility_assessment
        @waive_verification_obligation = waive_verification_obligation
        @register_merge_snapshot = register_merge_snapshot
        @submit_merge_snapshot_verification = submit_merge_snapshot_verification
        @request_merge_authorization = request_merge_authorization
        @record_merge_observation = record_merge_observation
        @prepare_release_set = prepare_release_set
        @record_repository_integration = record_repository_integration
        @record_release_set_verification = record_release_set_verification
        @record_release_set_activation = record_release_set_activation
        @complete_compensated_release_set = complete_compensated_release_set
        @publish_skill_revision = publish_skill_revision
        @capture_development_artifact = capture_development_artifact
        @correct_development_artifact_classification = correct_development_artifact_classification
        @declare_development_artifact_relation = declare_development_artifact_relation
        @create_operation_batch = operation_batch_command
        @cancel_operation_batch = operation_batch_command
      end

      def call(command, caused_by:)
        contract = TargetContractRegistry.fetch_by_command_class(command.class)
        contract.command_type[command]
        handler = instance_variable_get(contract.executor_variable)
        result = handler.call_command(command, caused_by:)
        result.fmap do |completion|
          contract.receipt_type[completion.data]
          completion
        end
      end
    end
  end
end
