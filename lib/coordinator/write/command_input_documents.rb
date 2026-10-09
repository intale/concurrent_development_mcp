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

    class RegisterRepositoryInputV1 < Value
      attribute :actor, ActorV1
      attribute :repository_id, Types::UuidV7
      attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
      attribute :repository_key, Types::Identifier
      attribute :display_name, Types::String.constrained(min_size: 1, max_size: 255).optional
      attribute :paths,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 1_024)).constrained(max_size: 20)
      attribute :remotes,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 2_048)).constrained(max_size: 20)
    end

    class RegisterRepositoryV1 < BaseV1
      attribute :tool_name, Types::String.enum("repository_register")
      attribute :input, RegisterRepositoryInputV1
    end

    class ResolveResourceInputV1 < Value
      attribute :actor, ActorV1
      attribute :repository_id, Types::RepositoryId
      attribute :kind, Types::ResourceKind
      attribute :path, Types::ResourcePath
    end

    class ResolveResourceV1 < BaseV1
      attribute :tool_name, Types::String.enum("resource_resolve")
      attribute :input, ResolveResourceInputV1
    end

    class RemoveResourceInputV1 < Value
      attribute :actor, ActorV1
      attribute :resource_id, Types::ResourceId
      attribute :reason, ResourceIdentityV1::UnbindingReason
    end

    class RemoveResourceV1 < BaseV1
      attribute :tool_name, Types::String.enum("resource_remove")
      attribute :input, RemoveResourceInputV1
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

    class AbandonAttemptInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end

    class AbandonAttemptV1 < BaseV1
      attribute :tool_name, Types::String.enum("attempt_abandon")
      attribute :input, AbandonAttemptInputV1
    end

    class WorkIntentionTargetV1 < Value
      attribute :resource_id, Types::ResourceId
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :mode, Types::WorkIntentionMode
      attribute :purpose, Types::WorkIntentionPurpose
      attribute :context, Types::WorkIntentionContext.optional
    end

    class DeclareWorkIntentionSetInputV1 < Value
      Resource = WorkIntentionTargetV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      attribute :ttl_seconds, Types::WorkIntentionTtlSeconds
    end

    class DeclareWorkIntentionSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_intention_set_declare")
      attribute :input, DeclareWorkIntentionSetInputV1
    end

    class ExpandWorkIntentionSetInputV1 < Value
      Resource = WorkIntentionTargetV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :intention_set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end

    class ExpandWorkIntentionSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_intention_set_expand")
      attribute :input, ExpandWorkIntentionSetInputV1
    end

    class WorkIntentionRenewalReferenceV1 < Value
      attribute :resource_id, Types::ResourceId
      attribute :intention_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class RenewWorkIntentionSetInputV1 < Value
      Reference = WorkIntentionRenewalReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :intention_set_id, Types::UuidV7
      attribute :intentions, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :ttl_seconds, Types::WorkIntentionTtlSeconds
    end

    class RenewWorkIntentionSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_intention_set_renew")
      attribute :input, RenewWorkIntentionSetInputV1
    end

    class WorkIntentionWithdrawalReferenceV1 < Value
      attribute :resource_id, Types::ResourceId
      attribute :intention_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class WithdrawWorkIntentionSetInputV1 < Value
      Reference = WorkIntentionWithdrawalReferenceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :intention_set_id, Types::UuidV7
      attribute :intentions, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end

    class WithdrawWorkIntentionSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_intention_set_withdraw")
      attribute :input, WithdrawWorkIntentionSetInputV1
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

    class CandidateWorkIntentionObservationV1 < Value
      attribute :resource_id, Types::ResourceId
      attribute :intention_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end

    class CandidateActualResourceV2 < Value
      attribute :kind, Types::String.enum("file")
      attribute :path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
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
      Intention = CandidateWorkIntentionObservationV1
      Resource = CandidateActualResourceV2

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
      attribute :intention_set_id, Types::UuidV7
      attribute :intentions, Types::Array.of(Intention).constrained(min_size: 1, max_size: 32)
      attribute :change_manifest, CandidateChangeManifestV1
      attribute :build_context, CandidateBuildContextV1.optional
      attribute :actual_resources,
                Types::Array.of(Resource).constrained(
                  min_size: 1,
                  max_size: Types::CANDIDATE_ACTUAL_RESOURCE_MAXIMUM_COUNT
                )
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
      attribute :claim_duration_seconds, Types::WorkIntentionTtlSeconds
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
      attribute :failure, ReleaseSets::IntegrationFailureV2.optional
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
      attribute :evidence, ReleaseSets::VerificationEvidenceV2
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
      attribute :activation_point, ReleaseSets::ActivationPointV2
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
      Evidence = ReleaseSets::CompensationEvidenceV2

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

    class SkillAssetV2 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute :path, Types::SkillAssetPath
      attribute :executable, Types::Bool
      attribute :content, Content
    end

    class PublishSkillRevisionBase < Value
      attribute :schema, Types::String.enum("command-input/v2")
      attribute :command_id, Types::Identifier
      attribute :tool_name, Types::String.enum("skill_publish")
    end

    class PublishSkillRevisionCanonicalInputV2 < Value
      Asset = SkillAssetV2

      attribute :actor, ActorV1
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :expected_revision, Types::SkillExpectedRevision
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
    end

    class PublishSkillRevisionInputV2 < PublishSkillRevisionCanonicalInputV2
      attribute :skill_id, Types::SkillId
    end

    class PublishSkillRevisionCanonicalV2 < PublishSkillRevisionBase
      attribute :input, PublishSkillRevisionCanonicalInputV2
    end

    class PublishSkillRevisionV2 < PublishSkillRevisionBase
      attribute :input, PublishSkillRevisionInputV2
    end

    class DevelopmentArtifactSourceV1 < Value
      attribute :kind, Types::DevelopmentArtifactSourceKind
      attribute :locator, Types::DevelopmentArtifactSourceLocator
      attribute :revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :observed_at, Types::Timestamp
      attribute :collector, Types::DevelopmentArtifactCollector
    end

    class DevelopmentArtifactCanonicalV2 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :content, Content
      attribute :source, DevelopmentArtifactSourceV1
    end

    class DevelopmentArtifactV2 < DevelopmentArtifactCanonicalV2
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :observation_id, Types::DevelopmentArtifactObservationId
    end

    class CaptureDevelopmentArtifactBase < Value
      attribute :schema, Types::String.enum("command-input/v2")
      attribute :command_id, Types::Identifier
      attribute :tool_name, Types::String.enum("development_artifact_capture")
    end

    class CaptureDevelopmentArtifactInputV2 < Value
      attribute :actor, ActorV1
      attribute :artifact, DevelopmentArtifactV2
    end

    class CaptureDevelopmentArtifactCanonicalInputV2 < Value
      attribute :actor, ActorV1
      attribute :artifact, DevelopmentArtifactCanonicalV2
    end

    class CaptureDevelopmentArtifactCanonicalV2 < CaptureDevelopmentArtifactBase
      attribute :input, CaptureDevelopmentArtifactCanonicalInputV2
    end

    class CaptureDevelopmentArtifactV2 < CaptureDevelopmentArtifactBase
      attribute :input, CaptureDevelopmentArtifactInputV2
    end

    class UpdateDevelopmentArtifactChangesV1 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute? :scope, Types::DevelopmentArtifactScope.optional
      attribute? :title, Types::DevelopmentArtifactTitle.optional
      attribute? :kind, Types::DevelopmentArtifactKind.optional
      attribute? :labels, Types::DevelopmentArtifactLabels.optional
      attribute? :content, Content.optional
      attribute? :source, DevelopmentArtifactSourceV1.optional
    end

    class UpdateDevelopmentArtifactInputV1 < Value
      attribute :actor, ActorV1
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :expected_revision, Types::Integer.constrained(gteq: 0)
      attribute :changes, UpdateDevelopmentArtifactChangesV1
    end

    class UpdateDevelopmentArtifactV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_update")
      attribute :input, UpdateDevelopmentArtifactInputV1
    end

    class CorrectDevelopmentArtifactClassificationInputV1 < Value
      attribute :actor, ActorV1
      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :expected_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 1_000)
    end

    class CorrectDevelopmentArtifactClassificationV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_classification_correct")
      attribute :input, CorrectDevelopmentArtifactClassificationInputV1
    end

    class DevelopmentArtifactRelationTargetV1 < Value
      attribute :kind, Types::DevelopmentArtifactTargetKind
      attribute :id, Types::DevelopmentArtifactTargetId
    end

    class DevelopmentArtifactRelationAttributesV1 < Value
      attribute :path, Types::DevelopmentArtifactRelationPath.optional
      attribute? :fragment, Types::DevelopmentArtifactRelationFragment.optional
      attribute? :normalized_locator, Types::DevelopmentArtifactSourceLocator.optional
    end

    class DevelopmentArtifactRelationCanonicalV1 < Value
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :relation, Types::DevelopmentArtifactRelationKind
      attribute :target, DevelopmentArtifactRelationTargetV1
      attribute :attributes, DevelopmentArtifactRelationAttributesV1

      def relation_attributes
        self[:attributes]
      end
    end

    class DevelopmentArtifactRelationV1 < DevelopmentArtifactRelationCanonicalV1
      attribute :relation_id, Types::DevelopmentArtifactRelationId
    end

    class DeclareDevelopmentArtifactRelationInputV1 < Value
      attribute :actor, ActorV1
      attribute :artifact_relation, DevelopmentArtifactRelationV1
      attribute? :supersedes_relation_id, Types::DevelopmentArtifactRelationId.optional
      attribute? :supersession_reason, Types::DevelopmentArtifactRelationSupersessionReason.optional
    end

    class DeclareDevelopmentArtifactRelationV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_relation_declare")
      attribute :input, DeclareDevelopmentArtifactRelationInputV1
    end

    class DeclareDevelopmentArtifactRelationCanonicalInputV1 < Value
      attribute :actor, ActorV1
      attribute :artifact_relation, DevelopmentArtifactRelationCanonicalV1
      attribute? :supersedes_relation_id, Types::DevelopmentArtifactRelationId.optional
      attribute? :supersession_reason, Types::DevelopmentArtifactRelationSupersessionReason.optional
    end

    class DeclareDevelopmentArtifactRelationCanonicalV1 < BaseV1
      attribute :tool_name, Types::String.enum("development_artifact_relation_declare")
      attribute :input, DeclareDevelopmentArtifactRelationCanonicalInputV1
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

    class OperationBatchItemRejectionV1 < Value
      attribute :code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
    end

    class RecordOperationBatchItemOutcomeInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
      attribute :index, Types::OperationBatchItemIndex
      attribute :item_command_id, Types::CommandId
      attribute :outcome, Types::String.enum("succeeded", "rejected")
      attribute :target_event, EventReferenceV1
      attribute :rejection, OperationBatchItemRejectionV1.optional
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
    end

    class RequestOperationBatchContinuationV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_continuation_policy")
      attribute :input, RequestOperationBatchContinuationInputV1
    end

    class CompleteOperationBatchInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
    end

    class CompleteOperationBatchV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_completion_policy")
      attribute :input, CompleteOperationBatchInputV1
    end

    class CompleteOperationBatchCancellationInputV1 < Value
      attribute :actor, ActorV1
      attribute :batch_id, Types::OperationBatchId
    end

    class CompleteOperationBatchCancellationV1 < BaseV1
      attribute :tool_name, Types::String.enum("operation_batch_cancellation_completion_policy")
      attribute :input, CompleteOperationBatchCancellationInputV1
    end

    class ExpireWorkIntentionInputV1 < Value
      attribute :actor, ActorV1
      attribute :resource_id, Types::ResourceId
      attribute :intention_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
      attribute :expected_expires_at, Types::Timestamp
    end

    class ExpireWorkIntentionV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_intention_expire_policy")
      attribute :input, ExpireWorkIntentionInputV1
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

    TARGET_TYPES = [
      RegisterRepositoryV1,
      ResolveResourceV1,
      RemoveResourceV1,
      CreateChangeSetV1,
      CreateWorkItemV1,
      DeclareWorkItemDependencyV1,
      ActivateChangeSetV1,
      AcquireWorkItemV1,
      CompleteWorkItemV1,
      AbandonAttemptV1,
      DeclareWorkIntentionSetV1,
      ExpandWorkIntentionSetV1,
      RenewWorkIntentionSetV1,
      WithdrawWorkIntentionSetV1,
      RecordGuidanceV1,
      ProposeDecisionInterpretationV1,
      AdjudicateDecisionInterpretationV1,
      ActivateDecisionV1,
      CorrectDecisionV1,
      RecordAgentChoiceV1,
      SubmitCandidateV1,
      SubmitCandidateImpactSurfaceV1,
      ClaimVerificationObligationV1,
      SubmitCompatibilityAssessmentV1,
      WaiveVerificationObligationV1,
      RegisterMergeSnapshotV1,
      SubmitMergeSnapshotVerificationV1,
      RequestMergeAuthorizationV1,
      RecordMergeObservationV1,
      PrepareReleaseSetV1,
      RecordRepositoryIntegrationV1,
      RecordReleaseSetVerificationV1,
      RecordReleaseSetActivationV1,
      CompleteCompensatedReleaseSetV1,
      PublishSkillRevisionV2,
      CaptureDevelopmentArtifactV2,
      UpdateDevelopmentArtifactV1,
      CorrectDevelopmentArtifactClassificationV1,
      DeclareDevelopmentArtifactRelationV1,
      CreateOperationBatchV1,
      CancelOperationBatchV1
    ].freeze
    Type = TARGET_TYPES.reduce { _1 | _2 }

    DigestType = Type |
                 ExpireWorkIntentionV1 |
                 RequestReleaseSetCompensationV1 |
                 CompleteActivatedReleaseSetV1 |
                 SatisfyWorkItemDependencyV1 |
                 CompleteChangeSetV1 |
                 RecordOperationBatchItemOutcomeV1 |
                 RequestOperationBatchContinuationV1 |
                 CompleteOperationBatchV1 |
                 CompleteOperationBatchCancellationV1

    CanonicalDigestType = DigestType |
                          PublishSkillRevisionCanonicalV2 |
                          CaptureDevelopmentArtifactCanonicalV2 |
                          UpdateDevelopmentArtifactV1 |
                          DeclareDevelopmentArtifactRelationCanonicalV1
  end
end
