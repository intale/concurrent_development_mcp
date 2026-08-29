# frozen_string_literal: true

module Coordinator::Write
  module CommandReceiptData
    class RepositoryRegistration < Value
      attribute :repository_id, Types::UuidV7
      attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
      attribute :display_name, Types::String.constrained(min_size: 1, max_size: 255).optional
      attribute :paths,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 1_024)).constrained(max_size: 20)
      attribute :remotes,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 2_048)).constrained(max_size: 20)
      attribute :registered_at, Types::Timestamp
    end

    class ResourceResolution < Value
      attribute :resource_id, Types::ResourceId
      attribute :repository_id, Types::RepositoryId
      attribute :kind, Types::ResourceKind
      attribute :normalized_path, Types::ResourcePath
      attribute :outcome, Types::String.enum("registered", "reactivated", "existing")
      attribute :registered_at, Types::Timestamp
      attribute :bound_at, Types::Timestamp
    end

    class ResourceRemoval < Value
      attribute :resource_id, Types::ResourceId
      attribute :repository_id, Types::RepositoryId
      attribute :kind, Types::ResourceKind
      attribute :normalized_path, Types::ResourcePath
      attribute :outcome, Types::String.enum("removed", "already_inactive", "superseded")
      attribute :reason, ResourceIdentityV1::UnbindingReason
      attribute :unbound_at, Types::Timestamp.optional
    end

    class ChangeSet < Value
      attribute :change_set_id, Types::Identifier
    end

    class WorkItem < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
    end

    class Dependency < Value
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
    end

    class Attempt < Value
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
    end

    class WorkItemCompletion < Value
      Output = WorkItemOutputV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :candidate_event, EventReference
      attribute :selected_event, EventReference
      attribute :attempt_completed_event, EventReference
      attribute :work_item_completed_event, EventReference
      attribute :produced_outputs,
                Types::Array.of(Output).constrained(max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT)
      attribute :completed_at, Types::Timestamp
    end

    class LeaseSet < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::ResourceKeyPolicyVersion
      attribute :acquired_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class LeaseSetExpansion < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::ResourceKeyPolicyVersion
      attribute :expanded_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :added_resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 31)
      attribute :resource_count, Types::ExpandedWriteSetSize
    end

    class LeaseSetRenewal < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::ResourceKeyPolicyVersion
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :renewed_at, Types::Timestamp
      attribute :previous_expires_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
    end

    class LeaseSetRelease < Value
      Reference = LeaseReferenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :lease_set_id, Types::UuidV7
      attribute :policy_version, Types::ResourceKeyPolicyVersion
      attribute :resources, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :resource_count, Types::WriteSetSize
      attribute :previous_expires_at, Types::Timestamp
      attribute :released_at, Types::Timestamp
    end

    class ResourceLeaseExpiry < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
      attribute :expired_at, Types::Timestamp
    end

    class Guidance < Value
      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :source, Types::GuidanceSource
      attribute :policy_status, Types::EvidencePolicyStatus
      attribute :recorded_at, Types::Timestamp
    end

    class InterpretationProposal < Value
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :assessment, Interpretations::InterpretationAssessmentV1
      attribute :proposed_at, Types::Timestamp
    end

    class InterpretationAdjudication < Value
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :action, Types::InterpretationAdjudicationAction
      attribute :outcome, Types::InterpretationAdjudicationOutcome
      attribute :policy_status, Types::InterpretationPolicyStatus
      attribute :slot, Interpretations::InterpretationSlotV1.optional
      attribute :adjudicated_at, Types::Timestamp
    end

    class DecisionActivation < Value
      PartitionReceipt = Decisions::DecisionPartitionReceiptV1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :outcome, Types::DecisionActivationOutcome
      attribute :policy_status, Types::DecisionPolicyStatus
      attribute :definition_digest, Types::Sha256Digest
      attribute :slot, Decisions::DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(PartitionReceipt).constrained(min_size: 1, max_size: 32)
      attribute :activated_at, Types::Timestamp
    end

    class DecisionCorrection < Value
      PartitionReceipt = Decisions::DecisionPartitionReceiptV1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :outcome, Types::DecisionCorrectionOutcome
      attribute :policy_status, Types::DecisionPolicyStatus
      attribute :previous_definition_digest, Types::Sha256Digest
      attribute :definition_digest, Types::Sha256Digest
      attribute :correction_event, EventReference
      attribute :slot, Decisions::DecisionSlotV1.optional
      attribute :partitions, Types::Array.of(PartitionReceipt).constrained(min_size: 1, max_size: 32)
      attribute :corrected_at, Types::Timestamp
    end

    class AgentChoice < Value
      Head = Decisions::DecisionHeadV1

      attribute :choice_id, Types::Identifier
      attribute :choice_type, Types::AgentChoiceType
      attribute :outcome, Types::AgentChoiceOutcome
      attribute :assessment_basis, Types::AgentChoiceAssessmentBasis
      attribute :context_digest, Types::Sha256Digest
      attribute :recorded_event, EventReference
      attribute :accepted_event, EventReference
      attribute :based_on_decisions, Types::Array.of(Head).constrained(max_size: 1)
      attribute :warnings, Types::Array.of(AgentChoices::ChoiceAssessmentV1::Warning).constrained(max_size: 10)
      attribute :accepted_at, Types::Timestamp
    end

    class CandidateSubmission < Value
      attribute :candidate_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :checkpoint_kind, Types::CandidateCheckpointKind
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :evidence_status, Types::CandidateEvidenceStatus
      attribute :candidate_event, EventReference
      attribute :submitted_at, Types::Timestamp
    end

    class CandidateImpactSurface < Value
      attribute :candidate_id, Types::Identifier
      attribute :surface_digest, Types::Sha256Digest
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :evidence_status, Types::CandidateEvidenceStatus
      attribute :surface_event, EventReference
      attribute :registration_event, EventReference
      attribute :derived_at, Types::Timestamp
    end

    class VerificationObligationClaim < Value
      attribute :obligation_id, Types::Identifier
      attribute :claim_id, Types::UuidV7
      attribute :claimant_id, Types::Identifier
      attribute :fencing_token, Types::FencingToken
      attribute :claimed_at, Types::Timestamp
      attribute :expires_at, Types::Timestamp
      attribute :claim_event, EventReference
    end

    class CompatibilityAssessment < Value
      attribute :obligation_id, Types::Identifier
      attribute :evidence_id, Types::UuidV7
      attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
      attribute :conclusion, Types::VerificationEvidenceConclusion
      attribute :status, Types::VerificationObligationStatus
      attribute :assessment_input_digest, Types::Sha256Digest
      attribute :evidence_event, EventReference
      attribute :outcome_event, EventReference.optional
      attribute :submitted_at, Types::Timestamp
    end

    class VerificationObligationWaiver < Value
      attribute :obligation_id, Types::Identifier
      attribute :previous_status, Types::String.enum("open", "failed")
      attribute :status, Types::String.enum("waived")
      attribute :reason, VerificationObligationWaivers::ReasonV1
      attribute :waiver_event, EventReference
      attribute :waived_at, Types::Timestamp
    end

    class MergeSnapshotRegistration < Value
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(MergeSnapshots::RequestedCandidateV1)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
      attribute :snapshot_digest, Types::Sha256Digest
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :snapshot_event, EventReference
      attribute :registered_at, Types::Timestamp
    end

    class MergeSnapshotVerification < Value
      attribute :merge_snapshot_id, Types::Identifier
      attribute :verification_id, Types::UuidV7
      attribute :evidence_kind, Types::MergeSnapshotVerificationEvidenceKind
      attribute :conclusion, Types::VerificationEvidenceConclusion
      attribute :status, Types::MergeSnapshotVerificationStatus
      attribute :verification_input_digest, Types::Sha256Digest
      attribute :submitted_event, EventReference
      attribute :verified_event, EventReference.optional
      attribute :submitted_at, Types::Timestamp
    end

    class MergeAuthorization < Value
      attribute :authorization_id, Types::UuidV7
      attribute :merge_snapshot_id, Types::Identifier
      attribute :outcome, Types::MergeAuthorizationOutcome
      attribute :decision_digest, Types::Sha256Digest
      attribute :decision_event, EventReference
      attribute :reasons,
                Types::Array.of(MergeAuthorizations::ReasonV1)
                  .constrained(max_size: Types::MERGE_AUTHORIZATION_MAXIMUM_REASONS)
      attribute :obligations,
                Types::Array.of(MergeAuthorizations::ObligationCheckV1)
                  .constrained(max_size: Types::MERGE_AUTHORIZATION_MAXIMUM_OBLIGATIONS)
      attribute :work_item_progress,
                Types::Array.of(MergeAuthorizations::WorkItemProgressV1)
                  .constrained(max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :decided_at, Types::Timestamp
    end

    class MergeObservation < Value
      attribute :merge_snapshot_id, Types::Identifier
      attribute :authorization_event, EventReference
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_before_commit_oid, Types::GitOid
      attribute :target_after_commit_oid, Types::GitOid
      attribute :observation_digest, Types::Sha256Digest
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :observation_event, EventReference
      attribute :observed_at, Types::Timestamp
      attribute :recorded_at, Types::Timestamp
    end

    class ReleaseSetPreparation < Value
      Member = ReleaseSets::MemberEvidenceV1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :ordered_members,
                Types::Array.of(Member)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :release_digest, Types::Sha256Digest
      attribute :policy_version, Types::ReleaseSetPreparationPolicyVersion
      attribute :prepared_event, EventReference
      attribute :prepared_at, Types::Timestamp
    end

    class RepositoryIntegration < Value
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :member_position, Types::ReleaseSetMemberPosition
      attribute :attempt_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetIntegrationAttemptNumber
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :integration_digest, Types::Sha256Digest
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :integration_event, EventReference
      attribute :recorded_at, Types::Timestamp
    end

    class ReleaseSetVerification < Value
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetVerificationAttemptNumber
      attribute :outcome, Types::ReleaseSetVerificationOutcome
      attribute :integration_events,
                Types::Array.of(EventReference)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :verification_digest, Types::Sha256Digest
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :verification_event, EventReference
      attribute :recorded_at, Types::Timestamp
    end

    class ReleaseSetActivation < Value
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :verification_event, EventReference
      attribute :verification_digest, Types::Sha256Digest
      attribute :activation_digest, Types::Sha256Digest
      attribute :evidence_status, Types::MergeSnapshotEvidenceStatus
      attribute :activation_event, EventReference
      attribute :recorded_at, Types::Timestamp
    end

    class ReleaseSetCompensationRequest < Value
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :trigger_event, EventReference
      attribute :trigger_kind, Types::ReleaseSetCompensationTriggerKind
      attribute :successful_integrations,
                Types::Array.of(EventReference)
                  .constrained(min_size: 1, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :compensation_request_event, EventReference
      attribute :requested_at, Types::Timestamp
    end

    class ReleaseSetCompletion < Value
      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :outcome, Types::ReleaseSetCompletionOutcome
      attribute :source_event, EventReference
      attribute :completion_digest, Types::Sha256Digest
      attribute :completion_event, EventReference
      attribute :completed_at, Types::Timestamp
    end

    class DependencySatisfaction < Value
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :source_event, EventReference
      attribute :satisfaction_event, EventReference
      attribute :readiness_event, EventReference.optional
      attribute :satisfied_at, Types::Timestamp
    end

    class ChangeSetCompletion < Value
      Evidence = ChangeSetCompletions::WorkItemEvidenceV1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_completions,
                Types::Array.of(Evidence).constrained(min_size: 1, max_size: 100)
      attribute :release_set_completion_event, EventReference.optional
      attribute :completion_event, EventReference
      attribute :completed_at, Types::Timestamp
    end

    class SkillPublication < Value
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :revision, Types::SkillRevision
      attribute :content_digest, Types::Sha256Digest
      attribute :asset_count,
                Types::Integer.constrained(gteq: 0, lteq: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :publication_event, EventReference
      attribute :published_at, Types::Timestamp
    end

    class DevelopmentArtifactCapture < Value
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::DevelopmentArtifactByteSize
      attribute :outcome, Types::String.enum("captured", "observed", "existing")
      attribute :recorded_at, Types::Timestamp
    end

    class DevelopmentArtifactClassification < Value
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :outcome, Types::String.enum("corrected", "existing")
      attribute :corrected_at, Types::Timestamp
    end

    class DevelopmentArtifactRelation < Value
      attribute :relation_id, Types::DevelopmentArtifactRelationId
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target, DevelopmentArtifacts::RelationTargetV1
      attribute :superseded_relation_id, Types::DevelopmentArtifactRelationId.optional
      attribute :outcome, Types::String.enum("declared", "existing", "superseded")
      attribute :declared_at, Types::Timestamp
      attribute :superseded_at, Types::Timestamp.optional
    end

    class OperationBatchAcceptance < Value
      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
      attribute :total, Types::OperationBatchTotal
      attribute :status, Types::String.enum("accepted")
    end

    class OperationBatchCancellation < Value
      attribute :batch_id, Types::OperationBatchId
      attribute :status, Types::String.enum("cancellation_requested")
    end

    class OperationBatchTransition < Value
      attribute :batch_id, Types::OperationBatchId
      attribute :transition, Types::String.enum(
        "item_succeeded",
        "item_rejected",
        "continuation_requested",
        "completed",
        "cancelled"
      )
      attribute :index, Types::OperationBatchItemIndex.optional
    end

    Type = RepositoryRegistration |
           ResourceResolution |
           ResourceRemoval |
           ChangeSet |
           WorkItem |
           Dependency |
           Attempt |
           WorkItemCompletion |
           LeaseSet |
           LeaseSetExpansion |
           LeaseSetRenewal |
           LeaseSetRelease |
           ResourceLeaseExpiry |
           Guidance |
           InterpretationProposal |
           InterpretationAdjudication |
           DecisionActivation |
           DecisionCorrection |
           AgentChoice |
           CandidateSubmission |
           CandidateImpactSurface |
           VerificationObligationClaim |
           CompatibilityAssessment |
           VerificationObligationWaiver |
           MergeSnapshotRegistration |
           MergeSnapshotVerification |
           MergeAuthorization |
           MergeObservation |
           ReleaseSetPreparation |
           RepositoryIntegration |
           ReleaseSetVerification |
           ReleaseSetActivation |
           ReleaseSetCompensationRequest |
           ReleaseSetCompletion |
           DependencySatisfaction |
           ChangeSetCompletion |
           SkillPublication |
           DevelopmentArtifactCapture |
           DevelopmentArtifactClassification |
           DevelopmentArtifactRelation |
           OperationBatchAcceptance |
           OperationBatchCancellation |
           OperationBatchTransition
  end
end
