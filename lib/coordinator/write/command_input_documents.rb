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
      attribute :files, Types::Array.of(File).constrained(min_size: 1, max_size: 256)
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

    Type = CreateChangeSetV1 |
           CreateWorkItemV1 |
           DeclareWorkItemDependencyV1 |
           ActivateChangeSetV1 |
           AcquireWorkItemV1 |
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
           RequestMergeAuthorizationV1

    DigestType = Type | ExpireResourceLeaseV1
  end
end
