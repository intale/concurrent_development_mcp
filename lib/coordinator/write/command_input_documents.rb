# frozen_string_literal: true

module Coordinator::Write
  module CommandInputDocuments
    class ActorV1 < Value
      attribute :actor_kind, Types::ActorKind
      attribute :actor_id, Types::Identifier
    end

    class BaseV1 < Value
      attribute :schema, Types::String.enum("command-input/v1")
      attribute :command_id, Types::Identifier
    end

    class CreateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::AcceptanceCriteria
    end

    class CreateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_create")
      attribute :input, CreateChangeSetInputV1
    end

    class CreateWorkItemInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::WorkItemAcceptanceCriteria
    end

    class CreateWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_create")
      attribute :input, CreateWorkItemInputV1
    end

    class DeclareWorkItemDependencyInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
    end

    class DeclareWorkItemDependencyV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_dependency_declare")
      attribute :input, DeclareWorkItemDependencyInputV1
    end

    class ActivateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
    end

    class ActivateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_activate")
      attribute :input, ActivateChangeSetInputV1
    end

    class RepositorySnapshotV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :commit_oid, Types::GitOid
    end

    class AcquireWorkItemInputV1 < Value
      Snapshot = RepositorySnapshotV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 100)
    end

    class AcquireWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_acquire")
      attribute :input, AcquireWorkItemInputV1
    end

    class CompleteWorkItemInputV1 < Value
      Output = WorkItemOutputV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :candidate_id, Types::Identifier
      attribute :produced_outputs,
                Types::Array.of(Output).constrained(max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT)
    end

    class CompleteWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_complete")
      attribute :input, CompleteWorkItemInputV1
    end

    class FileResourceV1 < Value
      attribute :kind, Types::ResourceKind
      attribute :path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :resource_key, Types::String
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
    end

    class ReserveWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end

    class ReserveWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_reserve")
      attribute :input, ReserveWriteSetInputV1
    end

    class ExpandWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end

    class ExpandWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_expand")
      attribute :input, ExpandWriteSetInputV1
    end

    class LeaseRenewalReferenceV1 < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class RenewLeaseSetInputV1 < Value
      Reference = LeaseRenewalReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end

    class RenewLeaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_renew")
      attribute :input, RenewLeaseSetInputV1
    end

    class LeaseReleaseReferenceV1 < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class ReleaseLeaseSetInputV1 < Value
      Reference = LeaseReleaseReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class ReleaseLeaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_release")
      attribute :input, ReleaseLeaseSetInputV1
    end

    class GuidanceAnchorsV1 < Value
      attribute :repository_ids, Types::GuidanceRepositoryIds
      attribute :change_set_id, Types::Identifier.optional
      attribute :work_item_id, Types::Identifier.optional
      attribute :attempt_id, Types::Identifier.optional
    end

    class RecordGuidanceInputV1 < Value
      attribute :actor, ActorV1
      attribute :message_id, Types::Identifier
      attribute :conversation_id, Types::Identifier
      attribute :source, Types::GuidanceSource
      attribute :text, Types::GuidanceText
      attribute :anchors, GuidanceAnchorsV1
    end

    class RecordGuidanceV1 < BaseV1
      attribute :tool_name, Types::String.enum("guidance_record")
      attribute :input, RecordGuidanceInputV1
    end

    class ProposeDecisionInterpretationInputV1 < Value
      Ambiguity = Interpretations::InterpretationAmbiguityV1

      attribute :actor, ActorV1
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_span, Interpretations::SourceSpanV1.optional
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :proposed_decision, Interpretations::SubmittedDecisionV1
      attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
    end

    class ProposeDecisionInterpretationV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_interpretation_propose")
      attribute :input, ProposeDecisionInterpretationInputV1
    end

    class AdjudicateDecisionInterpretationInputV1 < Value
      attribute :actor, ActorV1
      attribute :source_message_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :action, Types::InterpretationAdjudicationAction
      attribute :rationale, Interpretations::AdjudicationRationaleV1
      attribute :clarification, Interpretations::AdjudicationClarificationV1.optional
    end

    class AdjudicateDecisionInterpretationV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_interpretation_adjudicate")
      attribute :input, AdjudicateDecisionInterpretationInputV1
    end

    class ActivateDecisionInputV1 < Value
      attribute :actor, ActorV1
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :rationale, Decisions::DecisionActivationRationaleV1
    end

    class ActivateDecisionV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_activate")
      attribute :input, ActivateDecisionInputV1
    end

    class EventReferenceV1 < Value
      attribute :event_id, Types::UuidV7
      attribute :type, Types::Identifier
      attribute :stream_context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :stream_id, Types::Identifier
      attribute :stream_revision, Types::StreamRevision
    end

    class CorrectDecisionInputV1 < Value
      attribute :actor, ActorV1
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :expected_head, EventReferenceV1
      attribute :rationale, Decisions::DecisionCorrectionRationaleV1
    end

    class CorrectDecisionV1 < BaseV1
      attribute :tool_name, Types::String.enum("decision_correct")
      attribute :input, CorrectDecisionInputV1
    end

    class RecordAgentChoiceInputV1 < Value
      Option = AgentChoices::ChoiceOptionV1

      attribute :actor, ActorV1
      attribute :choice_id, Types::Identifier
      attribute :choice_type, Types::AgentChoiceType
      attribute :selected, Option
      attribute :alternatives, Types::Array.of(Option).constrained(max_size: 10)
      attribute :reason_summary, Types::String.constrained(min_size: 1, max_size: 1_000)
      attribute :context, DecisionContexts::QueryContextV1
      attribute :decision_context, DecisionContexts::ContextV1
    end

    class RecordAgentChoiceV1 < BaseV1
      attribute :tool_name, Types::String.enum("agent_choice_record")
      attribute :input, RecordAgentChoiceInputV1
    end

    class CandidateLeaseObservationV1 < Value
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class CandidateManifestFileV1 < Value
      attribute :status, Types::CandidateManifestStatus
      attribute :old_path, Types::ResourcePath.optional
      attribute :new_path, Types::ResourcePath.optional
      attribute :old_blob_oid, Types::GitOid.optional
      attribute :new_blob_oid, Types::GitOid.optional
      attribute :old_mode, Types::CandidateGitFileMode.optional
      attribute :new_mode, Types::CandidateGitFileMode.optional
    end

    class CandidateChangeManifestV1 < Value
      File = CandidateManifestFileV1

      attribute :policy_version, Types::String.enum(Candidates::ChangeManifestDocumentV1::SCHEMA)
      attribute :digest, Types::Sha256Digest
      attribute :collector_version, Types::CandidateCollectorVersion
      attribute :files,
                Types::Array.of(File).constrained(
                  min_size: 1,
                  max_size: Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT
                )
    end

    class CandidateBuildInputV1 < Value
      attribute :kind, Types::CandidateBuildInputKind
      attribute :path, Types::ResourcePath
      attribute :blob_oid, Types::GitOid
    end

    class CandidateEnvironmentEntryV1 < Value
      attribute :name, Types::CandidateEnvironmentName
      attribute :value, Types::CandidateEnvironmentValue
    end

    class CandidateBuildContextV1 < Value
      Input = CandidateBuildInputV1
      Environment = CandidateEnvironmentEntryV1

      attribute :policy_version, Types::String.enum(Candidates::BuildContextDocumentV1::SCHEMA)
      attribute :digest, Types::Sha256Digest
      attribute :collector_version, Types::CandidateCollectorVersion
      attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
      attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
      attribute :dependency_graph_digest, Types::Sha256Digest.optional
      attribute :test_environment_digest, Types::Sha256Digest.optional
    end

    class SubmitCandidateInputV1 < Value
      Lease = CandidateLeaseObservationV1
      Resource = FileResourceV1

      attribute :actor, ActorV1
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
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Lease).constrained(min_size: 1, max_size: 32)
      attribute :change_manifest, CandidateChangeManifestV1
      attribute :build_context, CandidateBuildContextV1.optional
      attribute :actual_resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end

    class SubmitCandidateV1 < BaseV1
      attribute :tool_name, Types::String.enum("candidate_submit")
      attribute :input, SubmitCandidateInputV1
    end

    class SubmitCandidateImpactSurfaceInputV1 < Value
      attribute :actor, ActorV1
      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :head_commit_oid, Types::GitOid
      attribute :manifest_digest, Types::Sha256Digest
      attribute :build_context_digest, Types::Sha256Digest.optional
      attribute :surface, Candidates::ImpactSurfaceV1
    end

    class SubmitCandidateImpactSurfaceV1 < BaseV1
      attribute :tool_name, Types::String.enum("candidate_impact_surface_submit")
      attribute :input, SubmitCandidateImpactSurfaceInputV1
    end

    class ClaimVerificationObligationInputV1 < Value
      attribute :actor, ActorV1
      attribute :obligation_id, Types::Identifier
      attribute :claim_duration_seconds, Types::LeaseDurationSeconds
    end

    class ClaimVerificationObligationV1 < BaseV1
      attribute :tool_name, Types::String.enum("verification_obligation_claim")
      attribute :input, ClaimVerificationObligationInputV1
    end

    class SubmitCompatibilityAssessmentInputV1 < Value
      attribute :actor, ActorV1
      attribute :obligation_id, Types::Identifier
      attribute :claim, CompatibilityAssessments::ClaimV1
      attribute :binding, CompatibilityAssessments::BindingV1
      attribute :assessment, CompatibilityAssessments::AssessmentV1
    end

    class SubmitCompatibilityAssessmentV1 < BaseV1
      attribute :tool_name, Types::String.enum("compatibility_assessment_submit")
      attribute :input, SubmitCompatibilityAssessmentInputV1
    end

    class WaiveVerificationObligationInputV1 < Value
      attribute :actor, ActorV1
      attribute :obligation_id, Types::Identifier
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :reason, VerificationObligationWaivers::ReasonV1
    end

    class WaiveVerificationObligationV1 < BaseV1
      attribute :tool_name, Types::String.enum("verification_obligation_waive")
      attribute :input, WaiveVerificationObligationInputV1
    end

    class MergeSnapshotCandidateV1 < Value
      attribute :candidate_id, Types::Identifier
      attribute :head_commit_oid, Types::GitOid
    end

    class MergeSnapshotProducerV1 < Value
      attribute :name, Types::MergeSnapshotProducerName
      attribute :version, Types::MergeSnapshotProducerVersion
    end

    class RegisterMergeSnapshotInputV1 < Value
      Candidate = MergeSnapshotCandidateV1

      attribute :actor, ActorV1
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Candidate)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
      attribute :producer, MergeSnapshotProducerV1
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
    end

    class RegisterMergeSnapshotV1 < BaseV1
      attribute :tool_name, Types::String.enum("merge_snapshot_register")
      attribute :input, RegisterMergeSnapshotInputV1
    end

    class SubmitMergeSnapshotVerificationInputV1 < Value
      attribute :actor, ActorV1
      attribute :merge_snapshot_id, Types::Identifier
      attribute :binding, MergeSnapshotVerifications::BindingV1
      attribute :assessment, MergeSnapshotVerifications::AssessmentV1
    end

    class SubmitMergeSnapshotVerificationV1 < BaseV1
      attribute :tool_name, Types::String.enum("merge_verification_submit")
      attribute :input, SubmitMergeSnapshotVerificationInputV1
    end

    class RequestMergeAuthorizationInputV1 < Value
      attribute :actor, ActorV1
      attribute :merge_snapshot_id, Types::Identifier
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :target_base_observation, MergeAuthorizations::TargetBaseObservationV1
      attribute :expected_impact_policy, MergeAuthorizations::ExpectedImpactPolicyV1.optional
    end

    class RequestMergeAuthorizationV1 < BaseV1
      attribute :tool_name, Types::String.enum("merge_authorization_request")
      attribute :input, RequestMergeAuthorizationInputV1
    end

    class RecordMergeObservationInputV1 < Value
      attribute :actor, ActorV1
      attribute :merge_snapshot_id, Types::Identifier
      attribute :authorization_event, EventReferenceV1
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_before_commit_oid, Types::GitOid
      attribute :target_after_commit_oid, Types::GitOid
      attribute :observer, MergeObservations::ObserverV1
      attribute :run_id, Types::Identifier
      attribute :observed_at, Types::Timestamp
    end

    class RecordMergeObservationV1 < BaseV1
      attribute :tool_name, Types::String.enum("merge_observation_record")
      attribute :input, RecordMergeObservationInputV1
    end

    class PrepareReleaseSetInputV1 < Value
      Member = ReleaseSets::RequestedMemberV1

      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :ordered_members,
                Types::Array.of(Member)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
    end

    class PrepareReleaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_set_prepare")
      attribute :input, PrepareReleaseSetInputV1
    end

    class RecordRepositoryIntegrationInputV1 < Value
      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :attempt_id, Types::Identifier
      attribute :outcome, Types::ReleaseSetIntegrationOutcome
      attribute :merge_observation_event, EventReferenceV1.optional
      attribute :observation_digest, Types::Sha256Digest.optional
      attribute :failure, ReleaseSets::IntegrationFailureV1.optional
    end

    class RecordRepositoryIntegrationV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_repository_integration_record")
      attribute :input, RecordRepositoryIntegrationInputV1
    end

    class RecordReleaseSetVerificationInputV1 < Value
      Reference = EventReferenceV1

      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :integration_events,
                Types::Array.of(Reference)
                  .constrained(
                    min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                    max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                  )
      attribute :evidence, ReleaseSets::VerificationEvidenceV1
    end

    class RecordReleaseSetVerificationV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_verification_record")
      attribute :input, RecordReleaseSetVerificationInputV1
    end

    class RecordReleaseSetActivationInputV1 < Value
      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :verification_event, EventReferenceV1
      attribute :verification_digest, Types::Sha256Digest
      attribute :activation_point, ReleaseSets::ActivationPointV1
    end

    class RecordReleaseSetActivationV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_activation_record")
      attribute :input, RecordReleaseSetActivationInputV1
    end

    class RequestReleaseSetCompensationInputV1 < Value
      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :trigger_event, EventReferenceV1
    end

    class RequestReleaseSetCompensationV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_compensation_request_policy")
      attribute :input, RequestReleaseSetCompensationInputV1
    end

    class CompleteActivatedReleaseSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :activation_event, EventReferenceV1
    end

    class CompleteActivatedReleaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_activated_complete_policy")
      attribute :input, CompleteActivatedReleaseSetInputV1
    end

    class CompleteCompensatedReleaseSetInputV1 < Value
      Evidence = ReleaseSets::CompensationEvidenceV1

      attribute :actor, ActorV1
      attribute :release_set_id, Types::Identifier
      attribute :compensation_request_event, EventReferenceV1
      attribute :evidence,
                Types::Array.of(Evidence)
                  .constrained(min_size: 1, max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
    end

    class CompleteCompensatedReleaseSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("release_compensation_complete")
      attribute :input, CompleteCompensatedReleaseSetInputV1
    end

    class SkillAssetV1 < Value
      attribute :path, Types::SkillAssetPath
      attribute :media_type, Types::SkillAssetMediaType
      attribute :executable, Types::Bool
      attribute :content_base64, Types::SkillAssetContentBase64
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::SkillAssetByteSize
    end

    class PublishSkillRevisionInputV1 < Value
      Asset = SkillAssetV1

      attribute :actor, ActorV1
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :expected_revision, Types::SkillExpectedRevision
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
    end

    class PublishSkillRevisionV1 < BaseV1
      attribute :tool_name, Types::String.enum("skill_publish")
      attribute :input, PublishSkillRevisionInputV1
    end

    class DevelopmentArtifactContentV1 < Value
      attribute :encoding, Types::DevelopmentArtifactEncoding
      attribute :media_type, Types::DevelopmentArtifactMediaType
      attribute :content_base64, Types::DevelopmentArtifactContentBase64
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::DevelopmentArtifactByteSize
    end

    class DevelopmentArtifactSourceV1 < Value
      attribute :kind, Types::DevelopmentArtifactSourceKind
      attribute :locator, Types::DevelopmentArtifactSourceLocator
      attribute :revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :observed_at, Types::Timestamp
      attribute :collector, Types::DevelopmentArtifactCollector
    end

    class DevelopmentArtifactV1 < Value
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :content, DevelopmentArtifactContentV1
      attribute :source, DevelopmentArtifactSourceV1
    end

    class CaptureDevelopmentArtifactInputV1 < Value
      attribute :actor, ActorV1
      attribute :artifact, DevelopmentArtifactV1
    end

    class CaptureDevelopmentArtifactV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_capture")
      attribute :input, CaptureDevelopmentArtifactInputV1
    end

    class DevelopmentArtifactRelationTargetV1 < Value
      attribute :kind, Types::DevelopmentArtifactTargetKind
      attribute :id, Types::DevelopmentArtifactTargetId
    end

    class DevelopmentArtifactRelationAttributesV1 < Value
      attribute :path, Types::DevelopmentArtifactRelationPath.optional
    end

    class DevelopmentArtifactRelationV1 < Value
      attribute :relation_id, Types::DevelopmentArtifactRelationId
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target, DevelopmentArtifactRelationTargetV1
      attribute :attributes, DevelopmentArtifactRelationAttributesV1

      def relation_attributes
        self[:attributes]
      end
    end

    class DeclareDevelopmentArtifactRelationInputV1 < Value
      attribute :actor, ActorV1
      attribute :artifact_relation, DevelopmentArtifactRelationV1
    end

    class DeclareDevelopmentArtifactRelationV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_relation_declare")
      attribute :input, DeclareDevelopmentArtifactRelationInputV1
    end

    class CreateOperationBatchInputV1 < Value
      Item = OperationBatches::ItemV1

      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
      attribute :items, Types::Array.of(Item).constrained(
        min_size: 1,
        max_size: Types::OPERATION_BATCH_MAXIMUM_ITEMS
      )
      attribute :manifest_digest, Types::Sha256Digest
      attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize
      attribute :page_size, Types::OperationBatchPageSize
    end

    class CreateOperationBatchV1 < BaseV1
      attribute :tool_name, Types::String.enum(
        "skill_publish_batch",
        "development_artifact_capture_batch",
        "development_artifact_relation_declare_batch"
      )
      attribute :input, CreateOperationBatchInputV1
    end

    class CancelOperationBatchInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
    end

    class CancelOperationBatchV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_cancel")
      attribute :input, CancelOperationBatchInputV1
    end

    class RecordOperationBatchItemOutcomeInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :item_command_id, Types::Identifier
      attribute :canonical_input_digest, Types::Sha256Digest
      attribute :result, Tasks::ToolResultV1
      attribute :target_completion, EventReferenceV1.optional
      attribute :finished_at, Types::Timestamp
    end

    class RecordOperationBatchItemOutcomeV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_item_outcome_policy")
      attribute :input, RecordOperationBatchItemOutcomeInputV1
    end

    class RequestOperationBatchContinuationInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :page_start, Types::OperationBatchItemIndex
      attribute :page_end, Types::OperationBatchItemIndex
      attribute :source_event, EventReferenceV1
      attribute :requested_at, Types::Timestamp
    end

    class RequestOperationBatchContinuationV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_continuation_policy")
      attribute :input, RequestOperationBatchContinuationInputV1
    end

    class CompleteOperationBatchInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :source_event, EventReferenceV1
      attribute :completed_at, Types::Timestamp
    end

    class CompleteOperationBatchV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_completion_policy")
      attribute :input, CompleteOperationBatchInputV1
    end

    class CompleteOperationBatchCancellationInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :source_event, EventReferenceV1
      attribute :cancelled_at, Types::Timestamp
    end

    class CompleteOperationBatchCancellationV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_cancellation_completion_policy")
      attribute :input, CompleteOperationBatchCancellationInputV1
    end

    class ExpireResourceLeaseInputV1 < Value
      attribute :actor, ActorV1
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :lease_id, Types::UuidV7
      attribute :lease_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end

    class ExpireResourceLeaseV1 < BaseV1
      attribute :tool_name, Types::String.enum("lease_expire_policy")
      attribute :input, ExpireResourceLeaseInputV1
    end

    class SatisfyWorkItemDependencyInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :source_event, EventReferenceV1
      attribute :rule_version, Types::String.enum("dependency-satisfaction/v1")
    end

    class SatisfyWorkItemDependencyV1 < BaseV1
      attribute :tool_name, Types::String.enum("dependency_satisfaction_policy")
      attribute :input, SatisfyWorkItemDependencyInputV1
    end

    class CompleteChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :source_event, EventReferenceV1
      attribute :release_set_id, Types::Identifier.optional
      attribute :rule_version, Types::String.enum("change-set-completion/v1")
    end

    class CompleteChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_completion_policy")
      attribute :input, CompleteChangeSetInputV1
    end

    Type = CreateChangeSetV1 |
           CreateWorkItemV1 |
           DeclareWorkItemDependencyV1 |
           ActivateChangeSetV1 |
           AcquireWorkItemV1 |
           CompleteWorkItemV1 |
           ReserveWriteSetV1 |
           ExpandWriteSetV1 |
           RenewLeaseSetV1 |
           ReleaseLeaseSetV1 |
           RecordGuidanceV1 |
           ProposeDecisionInterpretationV1 |
           AdjudicateDecisionInterpretationV1 |
           ActivateDecisionV1 |
           CorrectDecisionV1 |
           RecordAgentChoiceV1 |
           SubmitCandidateV1 |
           SubmitCandidateImpactSurfaceV1 |
           ClaimVerificationObligationV1 |
           SubmitCompatibilityAssessmentV1 |
           WaiveVerificationObligationV1 |
           RegisterMergeSnapshotV1 |
           SubmitMergeSnapshotVerificationV1 |
           RequestMergeAuthorizationV1 |
           RecordMergeObservationV1 |
           PrepareReleaseSetV1 |
           RecordRepositoryIntegrationV1 |
           RecordReleaseSetVerificationV1 |
           RecordReleaseSetActivationV1 |
           CompleteCompensatedReleaseSetV1 |
           PublishSkillRevisionV1 |
           CaptureDevelopmentArtifactV1 |
           DeclareDevelopmentArtifactRelationV1 |
           CreateOperationBatchV1 |
           CancelOperationBatchV1

    DigestType = Type |
                 ExpireResourceLeaseV1 |
                 RequestReleaseSetCompensationV1 |
                 CompleteActivatedReleaseSetV1 |
                 SatisfyWorkItemDependencyV1 |
                 CompleteChangeSetV1 |
                 RecordOperationBatchItemOutcomeV1 |
                 RequestOperationBatchContinuationV1 |
                 CompleteOperationBatchV1 |
                 CompleteOperationBatchCancellationV1
  end
end
