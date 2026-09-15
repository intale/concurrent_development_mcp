# frozen_string_literal: true

module Coordinator::Write
  class StreamFactory
    def command(command_id)
      StreamReference.new(context: "CoordinatorControl", stream_name: "Command", stream_id: command_id)
    end

    def coordination_task(task_id)
      StreamReference.new(context: "CoordinatorControl", stream_name: "CoordinationTask", stream_id: task_id)
    end

    def process_step(process_step_id)
      StreamReference.new(context: "CoordinatorControl", stream_name: "ProcessStep", stream_id: process_step_id)
    end

    def history_migration(migration_id)
      StreamReference.new(
        context: "CoordinatorMaintenance",
        stream_name: "HistoryMigration",
        stream_id: migration_id
      )
    end

    def history_migration_identity(identity_id)
      StreamReference.new(
        context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationIdentity",
        stream_id: identity_id
      )
    end

    def history_migration_correlation(correlation_id)
      StreamReference.new(
        context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationCorrelation",
        stream_id: correlation_id
      )
    end

    def history_migration_page(page_id)
      StreamReference.new(
        context: "CoordinatorMaintenance",
        stream_name: "HistoryMigrationPage",
        stream_id: page_id
      )
    end

    def skill(skill_id)
      StreamReference.new(context: "AgentKnowledge", stream_name: "Skill", stream_id: skill_id)
    end

    def skill_revision(skill_revision_id)
      StreamReference.new(
        context: "AgentKnowledge",
        stream_name: "SkillRevision",
        stream_id: skill_revision_id
      )
    end

    def skill_asset(asset_id)
      StreamReference.new(
        context: "AgentKnowledge",
        stream_name: "SkillAsset",
        stream_id: asset_id
      )
    end

    def operation_batch(batch_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "OperationBatch",
        stream_id: batch_id
      )
    end

    def development_artifact(artifact_id)
      StreamReference.new(
        context: "DevelopmentMemory",
        stream_name: "DevelopmentArtifact",
        stream_id: artifact_id
      )
    end

    def development_artifact_observation(observation_id)
      StreamReference.new(
        context: "DevelopmentMemory",
        stream_name: "DevelopmentArtifactObservation",
        stream_id: observation_id
      )
    end

    def development_artifact_relation(relation_id)
      StreamReference.new(
        context: "DevelopmentMemory",
        stream_name: "DevelopmentArtifactRelation",
        stream_id: relation_id
      )
    end

    def repository(repository_id)
      StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "Repository",
        stream_id: repository_id
      )
    end

    def resource(resource_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "Resource",
        stream_id: resource_id
      )
    end

    def change_set(change_set_id)
      StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: change_set_id
      )
    end

    def work_item(work_item_id)
      StreamReference.new(
        context: "DevelopmentExecution",
        stream_name: "WorkItem",
        stream_id: work_item_id
      )
    end

    def attempt(attempt_id)
      StreamReference.new(
        context: "DevelopmentExecution",
        stream_name: "Attempt",
        stream_id: attempt_id
      )
    end

    def resource_lease(resource_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "ResourceLease",
        stream_id: resource_id
      )
    end

    def work_intention_set(set_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "WorkIntentionSet",
        stream_id: set_id
      )
    end

    def resource_work_intention(intention_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "ResourceWorkIntention",
        stream_id: intention_id
      )
    end

    def resource_boundary_epoch(repository_id)
      StreamReference.new(
        context: "DevelopmentCoordination",
        stream_name: "ResourceBoundaryEpoch",
        stream_id: repository_id
      )
    end

    def conversation(conversation_id)
      StreamReference.new(
        context: "HumanGuidance",
        stream_name: "Conversation",
        stream_id: conversation_id
      )
    end

    def interpretation(message_id)
      StreamReference.new(
        context: "HumanGuidance",
        stream_name: "Interpretation",
        stream_id: message_id
      )
    end

    def decision(decision_id)
      StreamReference.new(
        context: "HumanGuidance",
        stream_name: "Decision",
        stream_id: decision_id
      )
    end

    def decision_slot(slot_id)
      StreamReference.new(
        context: "HumanGuidance",
        stream_name: "DecisionSlot",
        stream_id: slot_id
      )
    end

    def decision_partition(partition_id)
      StreamReference.new(
        context: "HumanGuidance",
        stream_name: "DecisionPartition",
        stream_id: partition_id
      )
    end

    def agent_choice(choice_id)
      StreamReference.new(
        context: "AgentGovernance",
        stream_name: "AgentChoice",
        stream_id: choice_id
      )
    end

    def agent_choice_impact_scan(scan_id)
      StreamReference.new(
        context: "AgentGovernance",
        stream_name: "AgentChoiceImpactScan",
        stream_id: scan_id
      )
    end

    def agent_choice_impact(assessment_id)
      StreamReference.new(
        context: "AgentGovernance",
        stream_name: "AgentChoiceImpact",
        stream_id: assessment_id
      )
    end

    def candidate(candidate_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "Candidate",
        stream_id: candidate_id
      )
    end

    def candidate_head(registry_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "CandidateHead",
        stream_id: registry_id
      )
    end

    def candidate_impact_surface(surface_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "CandidateImpactSurface",
        stream_id: surface_id
      )
    end

    def merge_snapshot(merge_snapshot_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "MergeSnapshot",
        stream_id: merge_snapshot_id
      )
    end

    def merge_verification(verification_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "MergeVerification",
        stream_id: verification_id
      )
    end

    def merge_authorization(authorization_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "MergeAuthorization",
        stream_id: authorization_id
      )
    end

    def merge_snapshot_commit(registry_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "MergeSnapshotCommit",
        stream_id: registry_id
      )
    end

    def release_set(release_set_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "ReleaseSet",
        stream_id: release_set_id
      )
    end

    def candidate_impact_registry(change_set_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "CandidateImpactRegistry",
        stream_id: change_set_id
      )
    end

    def candidate_impact_registry_sweep(scan_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "CandidateImpactRegistrySweep",
        stream_id: scan_id
      )
    end

    def candidate_impact_pair_scan(scan_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "CandidateImpactPairScan",
        stream_id: scan_id
      )
    end

    def verification_obligation(obligation_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "VerificationObligation",
        stream_id: obligation_id
      )
    end

    def verification_obligation_validity_scan(scan_id)
      StreamReference.new(
        context: "DevelopmentIntegration",
        stream_name: "VerificationObligationValidityScan",
        stream_id: scan_id
      )
    end
  end
end
