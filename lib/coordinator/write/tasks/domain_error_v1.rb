# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module DomainErrorV1
      class ChangeSetDetails < Value
        attribute :change_set_id, Types::Identifier
      end

      class ActivationDependencyDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :dependency_id, Types::Identifier
      end

      class WorkItemDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
      end

      class DependencyDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :dependency_id, Types::Identifier
        attribute :producer_work_item_id, Types::Identifier
        attribute :consumer_work_item_id, Types::Identifier
      end

      class AttemptDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
      end

      class WorkItemCompletionDetails < AttemptDetails
        attribute :candidate_id, Types::Identifier
      end

      class WorkItemCompletionActiveWriteSetDetails < WorkItemCompletionDetails
        attribute :lease_set_id, Types::UuidV7
        attribute :expires_at, Types::Timestamp
      end

      class CommandIdReusedDetails < Value
        attribute :command_id, Types::Identifier
        attribute :existing_tool_name, Types::Identifier
        attribute :existing_input_digest, Types::Sha256Digest
        attribute :requested_tool_name, Types::Identifier
        attribute :requested_input_digest, Types::Sha256Digest
      end

      class LeaseBusyDetails < Value
        attribute :resource_key, Types::String
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :lease_id, Types::UuidV7
        attribute :owner_attempt_id, Types::Identifier
        attribute :owner_agent_id, Types::Identifier
        attribute :fencing_token, Types::FencingToken
        attribute :expires_at, Types::Timestamp
      end

      class LeaseSetMismatchDetails < AttemptDetails
        attribute :current_lease_set_id, Types::UuidV7
        attribute :requested_lease_set_id, Types::UuidV7
      end

      class ResourceEvidenceConflictDetails < AttemptDetails
        attribute :resource_key, Types::String
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :current_base_blob_oid, Types::GitOid.optional
        attribute :requested_base_blob_oid, Types::GitOid.optional
      end

      class ResourceIdentityPolicyMismatchDetails < AttemptDetails
        attribute :current_policy_version, Types::ResourceKeyPolicyVersion
        attribute :requested_policy_version, Types::ResourceKeyPolicyVersion
      end

      class WriteSetLimitDetails < AttemptDetails
        attribute :current_resource_count, Types::WriteSetSize
        attribute :requested_addition_count, Types::WriteSetSize
      end

      class ResourceBoundaryMaintenanceDetails < Value
        attribute :repository_id, Types::UuidV7
        attribute :boundary_marker_count, Types::Integer.constrained(gteq: 1)
        attribute :maximum_delta_event_count,
                  Types::Integer.constrained(eql: EventQueries::RESOURCE_BOUNDARY_DECISION_DELTA_MAXIMUM_COUNT)
      end

      class LeaseSetExpiredDetails < AttemptDetails
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :lease_id, Types::UuidV7
        attribute :fencing_token, Types::FencingToken
        attribute :expires_at, Types::Timestamp
      end

      class LeaseSetNotCurrentDetails < AttemptDetails
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :expected_lease_id, Types::UuidV7
        attribute :current_lease_id, Types::UuidV7.optional
        attribute :expected_fencing_token, Types::FencingToken
        attribute :current_fencing_token, Types::Integer.constrained(gteq: 0)
        attribute :current_lease_set_id, Types::UuidV7.optional
        attribute :current_attempt_id, Types::Identifier.optional
        attribute :current_expires_at, Types::Timestamp.optional
        attribute :current_released_at, Types::Timestamp.optional
        attribute :current_expired_at, Types::Timestamp.optional
      end

      class WriteSetReleasedDetails < AttemptDetails
        attribute :released_at, Types::Timestamp
      end

      class LeaseSetSnapshotMismatchDetails < AttemptDetails
        attribute :current_resource_key_hashes, Types::Array.of(Types::Sha256Digest).constrained(max_size: 32)
        attribute :requested_resource_key_hashes, Types::Array.of(Types::Sha256Digest).constrained(max_size: 32)
      end

      class LeaseReferenceMismatchDetails < AttemptDetails
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :current_lease_id, Types::UuidV7
        attribute :requested_lease_id, Types::UuidV7
        attribute :current_fencing_token, Types::FencingToken
        attribute :requested_fencing_token, Types::FencingToken
      end

      class LeaseDeadlineNotExtendedDetails < AttemptDetails
        attribute :current_expires_at, Types::Timestamp
        attribute :requested_expires_at, Types::Timestamp
      end

      class MessageAlreadyRecordedDetails < Value
        attribute :message_id, Types::Identifier
      end

      class GuidanceMessageDetails < Value
        attribute :message_id, Types::Identifier
      end

      class InterpretationDetails < Value
        attribute :interpretation_id, Types::Identifier
      end

      class InterpretationMessageDetails < InterpretationDetails
        attribute :message_id, Types::Identifier
      end

      class InterpretationTerminalDetails < InterpretationDetails
        attribute :event_id, Types::UuidV7
      end

      class InterpretationSlotDetails < InterpretationTerminalDetails
        attribute :slot_digest, Types::Sha256Digest
      end

      class SourceSpanMismatchDetails < Value
        attribute :message_id, Types::Identifier
        attribute :interpretation_id, Types::Identifier
      end

      class TopicDetails < Value
        attribute :topic_id, Types::Identifier
      end

      class TopicValueDetails < Value
        attribute :topic_id, Types::Identifier
        attribute :expected_schema, Types::DecisionValueSchema
        attribute :supplied_schema, Types::DecisionValueSchema
      end

      class DecisionExistingDetails < Value
        attribute :decision_id, Types::Identifier
        attribute :event_id, Types::UuidV7
        attribute :event_type, Types::Identifier
      end

      class InterpretationActivationDetails < InterpretationDetails
        attribute :decision_id, Types::Identifier
        attribute :event_id, Types::UuidV7
      end

      class DecisionDefinitionIneligibleDetails < Value
        attribute :reasons, Types::DecisionActivationIneligibilityReasons
      end

      class DecisionSlotOccupiedDetails < Value
        attribute :slot_id, Types::Identifier
        attribute :decision_id, Types::Identifier
        attribute :event_id, Types::UuidV7
      end

      class DecisionPartitionLimitDetails < Value
        attribute :decision_id, Types::Identifier
        attribute :partition_count, Types::Integer.constrained(gteq: 33)
        attribute :maximum_partition_count, Types::Integer.constrained(eql: 32)
      end

      class DecisionPartitionCapacityDetails < Value
        attribute :partition_id, Types::Identifier
        attribute :active_decision_count, Types::Integer.constrained(gteq: 1, lteq: 32)
        attribute :maximum_active_decisions, Types::Integer.constrained(gteq: 1, lteq: 32)
      end

      class DecisionPartitionStateInvalidDetails < Value
        attribute :partition_id, Types::Identifier
        attribute :decision_id, Types::Identifier
        attribute :expected_head, Decisions::DecisionHeadV1
        attribute :observed_head, Decisions::DecisionHeadV1.optional
      end

      class DecisionIdentityDetails < Value
        attribute :decision_id, Types::Identifier
      end

      class DecisionLifecycleDetails < DecisionIdentityDetails
        attribute :event, EventReference
      end

      class InterpretationCorrectionRelationDetails < InterpretationDetails
        attribute :decision_id, Types::Identifier
        attribute :relations, Interpretations::DecisionRelationsV1
      end

      class DecisionCorrectionIneligibleDetails < Value
        attribute :reasons, Types::DecisionCorrectionIneligibilityReasons
      end

      class DecisionRevisionChangedDetails < DecisionIdentityDetails
        attribute :expected_head, EventReference
        attribute :current_head, EventReference
      end

      class DecisionSlotStateInvalidDetails < Value
        attribute :slot_id, Types::Identifier
        attribute :head, Decisions::DecisionHeadV1.optional
      end

      class AgentChoiceAlreadyExistsDetails < Value
        attribute :choice_id, Types::Identifier
        attribute :recorded_event, EventReference
      end

      class StaleDecisionContextDetails < Value
        attribute :changed_partition_ids, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 8)
        attribute :submitted_digest, Types::Sha256Digest
        attribute :current_digest, Types::Sha256Digest
        attribute :topic_id, Types::AgentChoiceType
        attribute :context, DecisionContexts::QueryContextV1
      end

      class DecisionContextMismatchDetails < Value
        attribute :submitted_digest, Types::Sha256Digest
        attribute :current_digest, Types::Sha256Digest
      end

      class DecisionContextConflictDetails < Value
        attribute :conflict, DecisionContexts::ConflictV1
      end

      class DecisionContextLimitDetails < Value
        attribute :partition_count, Types::Integer.constrained(gteq: 0)
        attribute :maximum_partition_count, Types::Integer.constrained(eql: 8)
        attribute :active_decision_count, Types::Integer.constrained(gteq: 0)
        attribute :maximum_active_decision_count, Types::Integer.constrained(eql: 32)
      end

      class UnsupportedDecisionContextDetails < Value
        attribute :dimensions, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 32)
        attribute :decision_heads, Types::Array.of(Decisions::DecisionHeadV1).constrained(min_size: 1, max_size: 32)
      end

      class AgentChoicePolicyDetails < Value
        attribute :decision_head, Decisions::DecisionHeadV1
        attribute :effect, Types::DecisionEffect
        attribute :selected_option_id, Types::Identifier
        attribute :decision_option_id, Types::Identifier
        attribute :on_violation, Types::ViolationAction
      end

      class AgentChoicePartitionSnapshotInvalidDetails < Value
        attribute :partition_id, Types::Identifier
        attribute :stream_revision, Types::StreamRevision
        attribute :reason, Types::String.enum("snapshot_invariant_violated")
      end

      class AgentChoiceDecisionHeadInvalidDetails < Value
        attribute :decision_id, Types::Identifier
        attribute :expected_head, Decisions::DecisionHeadV1
        attribute :current_head, Decisions::DecisionHeadV1.optional
      end

      class AgentChoiceUnresolvedHeadsDetails < Value
        attribute :decision_heads, Types::Array.of(Decisions::DecisionHeadV1).constrained(min_size: 1, max_size: 32)
      end

      class CandidateExistingDetails < Value
        attribute :candidate_id, Types::Identifier
        attribute :existing_event, EventReference
      end

      class CandidateHeadExistingDetails < CandidateExistingDetails
        attribute :repository_id, Types::RepositoryId
        attribute :object_format, Types::GitObjectFormat
        attribute :head_commit_oid, Types::GitOid
      end

      class CandidateLeaseObservationsMismatchDetails < Value
        attribute :attempt_id, Types::Identifier
        attribute :expected_resource_key_hashes,
                  Types::Array.of(Types::Sha256Digest).constrained(max_size: 32)
        attribute :submitted_resource_key_hashes,
                  Types::Array.of(Types::Sha256Digest).constrained(max_size: 32)
      end

      class CandidateLeaseNotActiveDetails < Value
        attribute :attempt_id, Types::Identifier
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :submitted_lease_id, Types::UuidV7
        attribute :current_lease_id, Types::UuidV7.optional
        attribute :current_fencing_token, Types::Integer.constrained(gteq: 0)
        attribute :expires_at, Types::Timestamp.optional
      end

      class CandidateUnauthorizedResource < Value
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :path, Types::ResourcePath
      end

      class CandidateUnauthorizedResourcesDetails < Value
        Resource = CandidateUnauthorizedResource

        attribute :candidate_id, Types::Identifier
        attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      end

      class CandidateManifestBaseMismatchDetails < Value
        attribute :candidate_id, Types::Identifier
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :path, Types::ResourcePath
        attribute :expected_base_blob_oid, Types::GitOid.optional
        attribute :submitted_base_blob_oid, Types::GitOid.optional
      end

      class CandidateImpactDetails < Value
        attribute :candidate_id, Types::Identifier
      end

      class CandidateImpactIdentityMismatchDetails < CandidateImpactDetails
        attribute :expected_repository_id, Types::RepositoryId
        attribute :expected_head_commit_oid, Types::GitOid
        attribute :submitted_repository_id, Types::RepositoryId
        attribute :submitted_head_commit_oid, Types::GitOid
      end

      class CandidateImpactSourceEvidenceMismatchDetails < CandidateImpactDetails
        attribute :expected_manifest_digest, Types::Sha256Digest.optional
        attribute :submitted_manifest_digest, Types::Sha256Digest
        attribute :expected_build_context_digest, Types::Sha256Digest.optional
        attribute :submitted_build_context_digest, Types::Sha256Digest.optional
      end

      class VerificationObligationDetails < Value
        attribute :obligation_id, Types::Identifier
      end

      class VerificationObligationActiveClaimDetails < VerificationObligationDetails
        attribute :claim_id, Types::UuidV7
        attribute :claimant_id, Types::Identifier
        attribute :fencing_token, Types::FencingToken
        attribute :expires_at, Types::Timestamp
      end

      class VerificationObligationClaimFenceDetails < VerificationObligationDetails
        attribute :current_claim_id, Types::UuidV7
        attribute :current_fencing_token, Types::FencingToken
      end

      class VerificationObligationClaimOwnerDetails < VerificationObligationDetails
        attribute :claimant_id, Types::Identifier
      end

      class VerificationObligationClaimExpiryDetails < VerificationObligationDetails
        attribute :expires_at, Types::Timestamp
      end

      class VerificationObligationBindingDetails < VerificationObligationDetails
        attribute :current_validity_input_digest, Types::Sha256Digest
      end

      class VerificationEvidenceKindDetails < VerificationObligationDetails
        attribute :evidence_kind, Types::CandidateImpactRequiredEvidenceKind
      end

      class VerificationEvidenceDigestDetails < VerificationObligationDetails
        attribute :assessment_input_digest, Types::Sha256Digest
      end

      class VerificationEvidenceLimitDetails < VerificationObligationDetails
        attribute :maximum_count, Types::Integer.enum(Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT)
      end

      class VerificationObligationTerminalDetails < VerificationObligationDetails
        attribute :status, Types::VerificationObligationStatus
      end

      class ChangeSetError < Value
        attribute :code, Types::String.enum(
          "change_set_already_exists",
          "change_set_not_found",
          "change_set_already_active",
          "change_set_has_no_criteria",
          "change_set_has_no_work_items",
          "dependency_cycle"
        )
        attribute :message, Types::String
        attribute :details, ChangeSetDetails
      end

      class ActivationDependencyError < Value
        attribute :code, Types::String.enum("dependency_endpoint_missing")
        attribute :message, Types::String
        attribute :details, ActivationDependencyDetails
      end

      class WorkItemError < Value
        attribute :code, Types::String.enum(
          "change_set_not_found",
          "change_set_not_draft",
          "work_item_already_exists",
          "work_item_limit_reached"
        )
        attribute :message, Types::String
        attribute :details, WorkItemDetails
      end

      class DependencyError < Value
        attribute :code, Types::String.enum(
          "change_set_not_found",
          "change_set_not_draft",
          "work_item_not_member",
          "dependency_self_reference",
          "dependency_id_reused",
          "dependency_limit_reached",
          "required_output_mismatch",
          "dependency_cycle"
        )
        attribute :message, Types::String
        attribute :details, DependencyDetails
      end

      class AttemptError < Value
        attribute :code, Types::String.enum(
          "change_set_not_active",
          "work_item_not_ready",
          "work_item_unavailable",
          "attempt_already_exists",
          "repository_base_mismatch",
          "attempt_not_found",
          "attempt_not_active",
          "attempt_scope_mismatch",
          "attempt_actor_mismatch",
          "attempt_owner_mismatch",
          "write_set_already_reserved",
          "write_set_not_reserved",
          "write_set_unchanged"
        )
        attribute :message, Types::String
        attribute :details, AttemptDetails
      end

      class WorkItemCompletionError < Value
        attribute :code, Types::String.enum(
          "change_set_not_active",
          "work_item_not_found",
          "work_item_scope_mismatch",
          "work_item_already_completed",
          "work_item_not_active",
          "attempt_owner_mismatch",
          "attempt_not_found",
          "attempt_already_completed",
          "attempt_scope_mismatch",
          "candidate_not_found",
          "candidate_scope_mismatch",
          "candidate_actor_mismatch",
          "candidate_not_final",
          "write_set_not_reserved"
        )
        attribute :message, Types::String
        attribute :details, WorkItemCompletionDetails
      end

      class WorkItemCompletionActiveWriteSetError < Value
        attribute :code, Types::String.enum("write_set_still_active")
        attribute :message, Types::String
        attribute :details, WorkItemCompletionActiveWriteSetDetails
      end

      class CommandIdReusedError < Value
        attribute :code, Types::String.enum("command_id_reused")
        attribute :message, Types::String
        attribute :details, CommandIdReusedDetails
      end

      class LeaseBusyError < Value
        attribute :code, Types::String.enum("lease_busy")
        attribute :message, Types::String
        attribute :details, LeaseBusyDetails
      end

      class LeaseSetMismatchError < Value
        attribute :code, Types::String.enum("lease_set_mismatch")
        attribute :message, Types::String
        attribute :details, LeaseSetMismatchDetails
      end

      class ResourceEvidenceConflictError < Value
        attribute :code, Types::String.enum("resource_evidence_conflict")
        attribute :message, Types::String
        attribute :details, ResourceEvidenceConflictDetails
      end

      class ResourceIdentityPolicyMismatchError < Value
        attribute :code, Types::String.enum("resource_identity_policy_mismatch")
        attribute :message, Types::String
        attribute :details, ResourceIdentityPolicyMismatchDetails
      end

      class WriteSetLimitError < Value
        attribute :code, Types::String.enum("write_set_limit_reached")
        attribute :message, Types::String
        attribute :details, WriteSetLimitDetails
      end

      class ResourceBoundaryMaintenanceRequiredError < Value
        attribute :code, Types::String.enum("resource_boundary_maintenance_required")
        attribute :message, Types::String
        attribute :details, ResourceBoundaryMaintenanceDetails
      end

      class LeaseSetExpiredError < Value
        attribute :code, Types::String.enum("lease_set_expired")
        attribute :message, Types::String
        attribute :details, LeaseSetExpiredDetails
      end

      class LeaseSetNotCurrentError < Value
        attribute :code, Types::String.enum("lease_set_not_current")
        attribute :message, Types::String
        attribute :details, LeaseSetNotCurrentDetails
      end

      class WriteSetReleasedError < Value
        attribute :code, Types::String.enum("write_set_released")
        attribute :message, Types::String
        attribute :details, WriteSetReleasedDetails
      end

      class LeaseSetSnapshotMismatchError < Value
        attribute :code, Types::String.enum("lease_set_snapshot_mismatch")
        attribute :message, Types::String
        attribute :details, LeaseSetSnapshotMismatchDetails
      end

      class LeaseReferenceMismatchError < Value
        attribute :code, Types::String.enum("lease_reference_mismatch")
        attribute :message, Types::String
        attribute :details, LeaseReferenceMismatchDetails
      end

      class LeaseDeadlineNotExtendedError < Value
        attribute :code, Types::String.enum("lease_deadline_not_extended")
        attribute :message, Types::String
        attribute :details, LeaseDeadlineNotExtendedDetails
      end

      class MessageAlreadyRecordedError < Value
        attribute :code, Types::String.enum("message_already_recorded")
        attribute :message, Types::String
        attribute :details, MessageAlreadyRecordedDetails
      end

      class GuidanceMessageNotFoundError < Value
        attribute :code, Types::String.enum("guidance_message_not_found")
        attribute :message, Types::String
        attribute :details, GuidanceMessageDetails
      end

      class InterpretationAlreadyProposedError < Value
        attribute :code, Types::String.enum("interpretation_already_proposed")
        attribute :message, Types::String
        attribute :details, InterpretationDetails
      end

      class InterpretationNotFoundError < Value
        attribute :code, Types::String.enum("interpretation_not_found")
        attribute :message, Types::String
        attribute :details, InterpretationMessageDetails
      end

      class InterpretationAlreadyAcceptedError < Value
        attribute :code, Types::String.enum("interpretation_already_accepted")
        attribute :message, Types::String
        attribute :details, InterpretationTerminalDetails
      end

      class InterpretationAlreadyRejectedError < Value
        attribute :code, Types::String.enum("interpretation_already_rejected")
        attribute :message, Types::String
        attribute :details, InterpretationTerminalDetails
      end

      class InterpretationSlotAlreadyAcceptedError < Value
        attribute :code, Types::String.enum("interpretation_slot_already_accepted")
        attribute :message, Types::String
        attribute :details, InterpretationSlotDetails
      end

      class SourceSpanMismatchError < Value
        attribute :code, Types::String.enum("source_span_mismatch")
        attribute :message, Types::String
        attribute :details, SourceSpanMismatchDetails
      end

      class TopicNotSupportedError < Value
        attribute :code, Types::String.enum("topic_not_supported")
        attribute :message, Types::String
        attribute :details, TopicDetails
      end

      class TopicValueInvalidError < Value
        attribute :code, Types::String.enum("topic_value_invalid")
        attribute :message, Types::String
        attribute :details, TopicValueDetails
      end

      class InterpretationNotAcceptedError < Value
        attribute :code, Types::String.enum("interpretation_not_accepted")
        attribute :message, Types::String
        attribute :details, InterpretationDetails
      end

      class DecisionAlreadyExistsError < Value
        attribute :code, Types::String.enum("decision_already_exists")
        attribute :message, Types::String
        attribute :details, DecisionExistingDetails
      end

      class InterpretationAlreadyActivatedError < Value
        attribute :code, Types::String.enum("interpretation_already_activated")
        attribute :message, Types::String
        attribute :details, InterpretationActivationDetails
      end

      class DecisionDefinitionNotActivatableError < Value
        attribute :code, Types::String.enum("decision_definition_not_activatable")
        attribute :message, Types::String
        attribute :details, DecisionDefinitionIneligibleDetails
      end

      class DecisionSlotOccupiedError < Value
        attribute :code, Types::String.enum("decision_slot_occupied")
        attribute :message, Types::String
        attribute :details, DecisionSlotOccupiedDetails
      end

      class DecisionPartitionLimitReachedError < Value
        attribute :code, Types::String.enum("decision_partition_limit_reached")
        attribute :message, Types::String
        attribute :details, DecisionPartitionLimitDetails
      end

      class DecisionPartitionCapacityReachedError < Value
        attribute :code, Types::String.enum("decision_partition_capacity_reached")
        attribute :message, Types::String
        attribute :details, DecisionPartitionCapacityDetails
      end

      class DecisionPartitionStateInvalidError < Value
        attribute :code, Types::String.enum("decision_partition_state_invalid")
        attribute :message, Types::String
        attribute :details, DecisionPartitionStateInvalidDetails
      end

      class DecisionNotFoundError < Value
        attribute :code, Types::String.enum("decision_not_found")
        attribute :message, Types::String
        attribute :details, DecisionIdentityDetails
      end

      class DecisionNotActiveError < Value
        attribute :code, Types::String.enum("decision_not_active")
        attribute :message, Types::String
        attribute :details, DecisionLifecycleDetails
      end

      class InterpretationNotACorrectionError < Value
        attribute :code, Types::String.enum("interpretation_not_a_correction")
        attribute :message, Types::String
        attribute :details, InterpretationCorrectionRelationDetails
      end

      class DecisionDefinitionNotCorrectableError < Value
        attribute :code, Types::String.enum("decision_definition_not_correctable")
        attribute :message, Types::String
        attribute :details, DecisionCorrectionIneligibleDetails
      end

      class DecisionRevisionChangedError < Value
        attribute :code, Types::String.enum("decision_revision_changed")
        attribute :message, Types::String
        attribute :details, DecisionRevisionChangedDetails
      end

      class DecisionSlotStateInvalidError < Value
        attribute :code, Types::String.enum("decision_slot_state_invalid")
        attribute :message, Types::String
        attribute :details, DecisionSlotStateInvalidDetails
      end

      class AgentChoiceAlreadyExistsError < Value
        attribute :code, Types::String.enum("agent_choice_already_exists")
        attribute :message, Types::String
        attribute :details, AgentChoiceAlreadyExistsDetails
      end

      class StaleDecisionContextError < Value
        attribute :code, Types::String.enum("stale_decision_context")
        attribute :message, Types::String
        attribute :details, StaleDecisionContextDetails
      end

      class DecisionContextMismatchError < Value
        attribute :code, Types::String.enum("decision_context_mismatch")
        attribute :message, Types::String
        attribute :details, DecisionContextMismatchDetails
      end

      class DecisionContextConflictError < Value
        attribute :code, Types::String.enum("decision_context_conflict")
        attribute :message, Types::String
        attribute :details, DecisionContextConflictDetails
      end

      class DecisionContextLimitReachedError < Value
        attribute :code, Types::String.enum("decision_context_limit_reached")
        attribute :message, Types::String
        attribute :details, DecisionContextLimitDetails
      end

      class UnsupportedDecisionContextError < Value
        attribute :code, Types::String.enum("unsupported_decision_context")
        attribute :message, Types::String
        attribute :details, UnsupportedDecisionContextDetails
      end

      class AgentChoiceBlockedByDecisionError < Value
        attribute :code, Types::String.enum("agent_choice_blocked_by_decision")
        attribute :message, Types::String
        attribute :details, AgentChoicePolicyDetails
      end

      class AgentChoiceConfirmationRequiredError < Value
        attribute :code, Types::String.enum("agent_choice_confirmation_required")
        attribute :message, Types::String
        attribute :details, AgentChoicePolicyDetails
      end

      class AgentChoicePartitionSnapshotInvalidError < Value
        attribute :code, Types::String.enum("decision_partition_state_invalid")
        attribute :message, Types::String
        attribute :details, AgentChoicePartitionSnapshotInvalidDetails
      end

      class AgentChoiceDecisionHeadInvalidError < Value
        attribute :code, Types::String.enum("decision_partition_state_invalid")
        attribute :message, Types::String
        attribute :details, AgentChoiceDecisionHeadInvalidDetails
      end

      class AgentChoiceUnresolvedHeadsError < Value
        attribute :code, Types::String.enum("decision_partition_state_invalid")
        attribute :message, Types::String
        attribute :details, AgentChoiceUnresolvedHeadsDetails
      end

      class CandidateAlreadyExistsError < Value
        attribute :code, Types::String.enum("candidate_id_already_used")
        attribute :message, Types::String
        attribute :details, CandidateExistingDetails
      end

      class CandidateHeadAlreadyRegisteredError < Value
        attribute :code, Types::String.enum("candidate_head_already_registered")
        attribute :message, Types::String
        attribute :details, CandidateHeadExistingDetails
      end

      class CandidateLeaseObservationsMismatchError < Value
        attribute :code, Types::String.enum("lease_observations_mismatch")
        attribute :message, Types::String
        attribute :details, CandidateLeaseObservationsMismatchDetails
      end

      class CandidateLeaseNotActiveScopeError < Value
        attribute :code, Types::String.enum("lease_not_active")
        attribute :message, Types::String
        attribute :details, AttemptDetails
      end

      class CandidateLeaseNotActiveError < Value
        attribute :code, Types::String.enum("lease_not_active")
        attribute :message, Types::String
        attribute :details, CandidateLeaseNotActiveDetails
      end

      class CandidateUnauthorizedResourcesError < Value
        attribute :code, Types::String.enum("actual_write_set_not_authorized")
        attribute :message, Types::String
        attribute :details, CandidateUnauthorizedResourcesDetails
      end

      class CandidateManifestBaseMismatchError < Value
        attribute :code, Types::String.enum("manifest_base_evidence_mismatch")
        attribute :message, Types::String
        attribute :details, CandidateManifestBaseMismatchDetails
      end

      class CandidateNotFoundError < Value
        attribute :code, Types::String.enum("candidate_not_found")
        attribute :message, Types::String
        attribute :details, CandidateImpactDetails
      end

      class CandidateImpactIdentityMismatchError < Value
        attribute :code, Types::String.enum("candidate_impact_identity_mismatch")
        attribute :message, Types::String
        attribute :details, CandidateImpactIdentityMismatchDetails
      end

      class CandidateImpactSourceEvidenceMismatchError < Value
        attribute :code, Types::String.enum("candidate_impact_source_evidence_mismatch")
        attribute :message, Types::String
        attribute :details, CandidateImpactSourceEvidenceMismatchDetails
      end

      class CandidateImpactSurfaceAlreadyRecordedError < Value
        attribute :code, Types::String.enum("candidate_impact_surface_already_recorded")
        attribute :message, Types::String
        attribute :details, CandidateExistingDetails
      end

      class RepositoryIdentityDetails < Value
        attribute :repository_id, Types::UuidV7
        attribute :requested_scope, Types::String.constrained(min_size: 1, max_size: 500)
        attribute :registered_scope, Types::String.constrained(min_size: 1, max_size: 500)
      end

      class RepositoryRegistrationError < Value
        attribute :code, Types::String.enum(
          "repository_already_registered",
          "repository_identity_conflict"
        )
        attribute :message, Types::String
        attribute :details, RepositoryIdentityDetails
      end

      class RepositoryNotRegisteredDetails < Value
        attribute :repository_id, Types::UuidV7
      end

      class RepositoryNotRegisteredError < Value
        attribute :code, Types::String.enum("repository_not_registered")
        attribute :message, Types::String
        attribute :details, RepositoryNotRegisteredDetails
      end

      class SkillIdentityDetails < Value
        attribute :skill_id, Types::SkillId
        attribute :name, Types::SkillName
        attribute :scope, Types::SkillScope
      end

      class SkillRevisionDetails < SkillIdentityDetails
        attribute :expected_revision, Types::SkillExpectedRevision
        attribute :current_revision, Types::Integer.constrained(gteq: 0)
      end

      class SkillIdentityConflictError < Value
        attribute :code, Types::String.enum("skill_identity_conflict")
        attribute :message, Types::String
        attribute :details, SkillIdentityDetails
      end

      class SkillRevisionConflictError < Value
        attribute :code, Types::String.enum("skill_revision_conflict")
        attribute :message, Types::String
        attribute :details, SkillRevisionDetails
      end

      class DevelopmentArtifactDetails < Value
        attribute :artifact_id, Types::DevelopmentArtifactId
      end

      class DevelopmentArtifactTargetDetails < DevelopmentArtifactDetails
        attribute :target_artifact_id, Types::DevelopmentArtifactId
      end

      class DevelopmentArtifactRelationLimitDetails < DevelopmentArtifactDetails
        attribute :relation_count, Types::Integer.constrained(gteq: 0)
        attribute :maximum_relation_count,
                  Types::Integer.constrained(
                    eql: Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
                  )
      end

      class DevelopmentArtifactIdentityConflictError < Value
        attribute :code, Types::String.enum("development_artifact_identity_conflict")
        attribute :message, Types::String
        attribute :details, DevelopmentArtifactDetails
      end

      class DevelopmentArtifactNotFoundError < Value
        attribute :code, Types::String.enum("development_artifact_not_found")
        attribute :message, Types::String
        attribute :details, DevelopmentArtifactDetails
      end

      class DevelopmentArtifactTargetNotFoundError < Value
        attribute :code, Types::String.enum("development_artifact_target_not_found")
        attribute :message, Types::String
        attribute :details, DevelopmentArtifactTargetDetails
      end

      class DevelopmentArtifactRelationLimitReachedError < Value
        attribute :code, Types::String.enum("development_artifact_relation_limit_reached")
        attribute :message, Types::String
        attribute :details, DevelopmentArtifactRelationLimitDetails
      end

      class VerificationObligationNotFoundError < Value
        attribute :code, Types::String.enum("verification_obligation_not_found")
        attribute :message, Types::String
        attribute :details, VerificationObligationDetails
      end

      class VerificationObligationAlreadyClaimedError < Value
        attribute :code, Types::String.enum("verification_obligation_already_claimed")
        attribute :message, Types::String
        attribute :details, VerificationObligationActiveClaimDetails
      end

      class VerificationObligationPolicyStaleError < Value
        attribute :code, Types::String.enum("verification_obligation_policy_stale")
        attribute :message, Types::String
        attribute :details, VerificationObligationDetails
      end

      class VerificationObligationUnclaimedError < Value
        attribute :code, Types::String.enum("verification_obligation_unclaimed")
        attribute :message, Types::String
        attribute :details, VerificationObligationDetails
      end

      class VerificationObligationClaimStaleError < Value
        attribute :code, Types::String.enum("verification_obligation_claim_stale")
        attribute :message, Types::String
        attribute :details, VerificationObligationClaimFenceDetails
      end

      class VerificationObligationClaimNotOwnedError < Value
        attribute :code, Types::String.enum("verification_obligation_claim_not_owned")
        attribute :message, Types::String
        attribute :details, VerificationObligationClaimOwnerDetails
      end

      class VerificationObligationClaimExpiredError < Value
        attribute :code, Types::String.enum("verification_obligation_claim_expired")
        attribute :message, Types::String
        attribute :details, VerificationObligationClaimExpiryDetails
      end

      class VerificationObligationBindingStaleError < Value
        attribute :code, Types::String.enum("verification_obligation_binding_stale")
        attribute :message, Types::String
        attribute :details, VerificationObligationBindingDetails
      end

      class VerificationEvidenceKindNotRequiredError < Value
        attribute :code, Types::String.enum("verification_evidence_kind_not_required")
        attribute :message, Types::String
        attribute :details, VerificationEvidenceKindDetails
      end

      class VerificationEvidenceAlreadySubmittedError < Value
        attribute :code, Types::String.enum("verification_evidence_already_submitted")
        attribute :message, Types::String
        attribute :details, VerificationEvidenceDigestDetails
      end

      class VerificationEvidenceLimitReachedError < Value
        attribute :code, Types::String.enum("verification_evidence_limit_reached")
        attribute :message, Types::String
        attribute :details, VerificationEvidenceLimitDetails
      end

      class VerificationObligationTerminalError < Value
        attribute :code, Types::String.enum("verification_obligation_terminal")
        attribute :message, Types::String
        attribute :details, VerificationObligationTerminalDetails
      end

      class VerificationObligationWaiverRequiresUserError < Value
        attribute :code, Types::String.enum("verification_obligation_waiver_requires_user")
        attribute :message, Types::String
        attribute :details, VerificationObligationDetails
      end

      class VerificationObligationAlreadyWaivedError < Value
        attribute :code, Types::String.enum("verification_obligation_already_waived")
        attribute :message, Types::String
        attribute :details, VerificationObligationTerminalDetails
      end

      class MergeSnapshotExistingDetails < Value
        attribute :existing_event, EventReference
      end

      class MergeSnapshotCandidateDetails < Value
        attribute :candidate_id, Types::Identifier
        attribute :requested_head_commit_oid, Types::GitOid
      end

      class MergeSnapshotDetails < Value
        attribute :merge_snapshot_id, Types::Identifier
      end

      class MergeSnapshotBindingDetails < MergeSnapshotDetails
        attribute :current_snapshot_event, EventReference
        attribute :current_snapshot_digest, Types::Sha256Digest
      end

      class MergeSnapshotVerificationDigestDetails < MergeSnapshotDetails
        attribute :verification_input_digest, Types::Sha256Digest
      end

      class MergeSnapshotVerificationLimitDetails < MergeSnapshotDetails
        attribute :maximum_count,
                  Types::Integer.enum(Types::MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT)
      end

      class OperationBatchDetails < Value
        attribute :batch_id, Types::OperationBatchId
      end

      class OperationBatchItemDetails < OperationBatchDetails
        attribute :index, Types::OperationBatchItemIndex
      end

      class MergeObservationExistingDetails < Value
        attribute :existing_event, EventReference
      end

      class MergeObservationMismatchDetails < Value
        attribute :merge_snapshot_id, Types::Identifier
        attribute :expected_repository_id, Types::RepositoryId.optional
        attribute :expected_target_branch, Types::CandidateTargetBranch.optional
        attribute :expected_object_format, Types::GitObjectFormat.optional
        attribute :expected_before_commit_oid, Types::GitOid.optional
        attribute :expected_after_commit_oid, Types::GitOid.optional
      end

      class MergeAuthorizationStaleDetails < Value
        attribute :reasons, Types::Array.of(MergeAuthorizations::ReasonV1)
      end

      class MergeObservationStateDetails < Value
        attribute? :merge_snapshot_id, Types::Identifier
      end

      class ReleaseSetDetails < Value
        attribute? :release_set_id, Types::Identifier
      end

      class ReleaseSetExistingDetails < ReleaseSetDetails
        attribute :existing_event, EventReference
      end

      class MergeSnapshotExistingError < Value
        attribute :code, Types::String.enum(
          "merge_snapshot_id_already_used",
          "merge_commit_already_registered"
        )
        attribute :message, Types::String
        attribute :details, MergeSnapshotExistingDetails
      end

      class MergeSnapshotCandidateError < Value
        attribute :code, Types::String.enum(
          "candidate_not_found",
          "candidate_manifest_not_found",
          "candidate_head_mismatch",
          "candidate_repository_mismatch",
          "candidate_target_branch_mismatch",
          "candidate_object_format_mismatch"
        )
        attribute :message, Types::String
        attribute :details, MergeSnapshotCandidateDetails
      end

      class MergeSnapshotStateError < Value
        attribute :code, Types::String.enum(
          "merge_snapshot_not_found",
          "merge_snapshot_already_verified"
        )
        attribute :message, Types::String
        attribute :details, MergeSnapshotDetails
      end

      class MergeSnapshotVerificationBindingStaleError < Value
        attribute :code, Types::String.enum("merge_snapshot_verification_binding_stale")
        attribute :message, Types::String
        attribute :details, MergeSnapshotBindingDetails
      end

      class MergeSnapshotVerificationAlreadySubmittedError < Value
        attribute :code, Types::String.enum("merge_snapshot_verification_already_submitted")
        attribute :message, Types::String
        attribute :details, MergeSnapshotVerificationDigestDetails
      end

      class MergeSnapshotVerificationLimitReachedError < Value
        attribute :code, Types::String.enum("merge_snapshot_verification_limit_reached")
        attribute :message, Types::String
        attribute :details, MergeSnapshotVerificationLimitDetails
      end

      class OperationBatchError < Value
        attribute :code, Types::String.enum(
          "operation_batch_id_conflict",
          "operation_batch_not_found",
          "operation_batch_terminal",
          "operation_batch_cancellation_already_requested",
          "operation_batch_cancellation_pending",
          "operation_batch_ready_to_complete",
          "operation_batch_continuation_invalid",
          "operation_batch_items_pending",
          "operation_batch_cancellation_not_requested"
        )
        attribute :message, Types::String
        attribute :details, OperationBatchDetails
      end

      class OperationBatchItemError < Value
        attribute :code, Types::String.enum(
          "operation_batch_item_not_found",
          "operation_batch_item_already_recorded"
        )
        attribute :message, Types::String
        attribute :details, OperationBatchItemDetails
      end

      class MergeObservationExistingError < Value
        attribute :code, Types::String.enum("merge_already_observed")
        attribute :message, Types::String
        attribute :details, MergeObservationExistingDetails
      end

      class MergeObservationStateError < Value
        attribute :code, Types::String.enum(
          "merge_authorization_not_found",
          "merge_authorization_binding_stale"
        )
        attribute :message, Types::String
        attribute :details, MergeObservationStateDetails
      end

      class MergeAuthorizationStaleError < Value
        attribute :code, Types::String.enum("merge_authorization_stale")
        attribute :message, Types::String
        attribute :details, MergeAuthorizationStaleDetails
      end

      class MergeObservationMismatchError < Value
        attribute :code, Types::String.enum("merge_observation_mismatch")
        attribute :message, Types::String
        attribute :details, MergeObservationMismatchDetails
      end

      class ReleaseSetExistingError < Value
        attribute :code, Types::String.enum("release_set_id_already_used")
        attribute :message, Types::String
        attribute :details, ReleaseSetExistingDetails
      end

      class ReleaseSetError < Value
        attribute :code, Types::String.enum(
          "release_set_repositories_repeated",
          "release_set_snapshots_repeated",
          "release_set_change_sets_mixed",
          "release_set_not_found",
          "release_set_already_completed",
          "release_set_compensation_requested",
          "release_set_already_activated",
          "release_member_not_found",
          "release_integration_attempt_reused",
          "release_member_already_integrated",
          "release_integration_attempt_limit_reached",
          "release_integration_out_of_order",
          "release_integration_evidence_invalid",
          "release_integration_observation_mismatch",
          "release_set_integrations_incomplete",
          "release_set_already_verified",
          "release_verification_attempt_limit_reached",
          "release_verification_integration_binding_stale",
          "release_verification_evidence_invalid",
          "release_set_not_verified",
          "release_activation_verification_binding_stale",
          "release_compensation_not_requested",
          "release_compensation_request_binding_stale",
          "release_compensation_evidence_mismatch",
          "release_set_not_activated",
          "release_activation_binding_stale",
          "release_set_compensation_already_requested",
          "release_compensation_trigger_not_found",
          "release_compensation_not_required",
          "release_compensation_trigger_invalid"
        )
        attribute :message, Types::String
        attribute :details, ReleaseSetDetails
      end

      BaseType = ChangeSetError |
             ActivationDependencyError |
             WorkItemError |
             DependencyError |
             AttemptError |
             WorkItemCompletionError |
             WorkItemCompletionActiveWriteSetError |
             CommandIdReusedError |
             LeaseBusyError |
             LeaseSetMismatchError |
             ResourceEvidenceConflictError |
             ResourceIdentityPolicyMismatchError |
             WriteSetLimitError |
             ResourceBoundaryMaintenanceRequiredError |
             LeaseSetExpiredError |
             LeaseSetNotCurrentError |
             WriteSetReleasedError |
             LeaseSetSnapshotMismatchError |
             LeaseReferenceMismatchError |
             LeaseDeadlineNotExtendedError |
             MessageAlreadyRecordedError |
             GuidanceMessageNotFoundError |
             InterpretationAlreadyProposedError |
             InterpretationNotFoundError |
             InterpretationAlreadyAcceptedError |
             InterpretationAlreadyRejectedError |
             InterpretationSlotAlreadyAcceptedError |
             SourceSpanMismatchError |
             TopicNotSupportedError |
             TopicValueInvalidError |
             InterpretationNotAcceptedError |
             DecisionAlreadyExistsError |
             InterpretationAlreadyActivatedError |
             DecisionDefinitionNotActivatableError |
             DecisionSlotOccupiedError |
             DecisionPartitionLimitReachedError |
             DecisionPartitionCapacityReachedError |
             DecisionPartitionStateInvalidError |
             DecisionNotFoundError |
             DecisionNotActiveError |
             InterpretationNotACorrectionError |
             DecisionDefinitionNotCorrectableError |
             DecisionRevisionChangedError |
             DecisionSlotStateInvalidError |
             AgentChoiceAlreadyExistsError |
             StaleDecisionContextError |
             DecisionContextMismatchError |
             DecisionContextConflictError |
             DecisionContextLimitReachedError |
             UnsupportedDecisionContextError |
             AgentChoiceBlockedByDecisionError |
             AgentChoiceConfirmationRequiredError |
             AgentChoicePartitionSnapshotInvalidError |
             AgentChoiceDecisionHeadInvalidError |
             AgentChoiceUnresolvedHeadsError |
             CandidateAlreadyExistsError |
             CandidateHeadAlreadyRegisteredError |
             CandidateLeaseObservationsMismatchError |
             CandidateLeaseNotActiveScopeError |
             CandidateLeaseNotActiveError |
             CandidateUnauthorizedResourcesError |
             CandidateManifestBaseMismatchError |
             CandidateNotFoundError |
             CandidateImpactIdentityMismatchError |
             CandidateImpactSourceEvidenceMismatchError |
             CandidateImpactSurfaceAlreadyRecordedError |
             RepositoryRegistrationError |
             RepositoryNotRegisteredError |
             SkillIdentityConflictError |
             SkillRevisionConflictError |
             DevelopmentArtifactIdentityConflictError |
             DevelopmentArtifactNotFoundError |
             DevelopmentArtifactTargetNotFoundError |
             DevelopmentArtifactRelationLimitReachedError |
             VerificationObligationNotFoundError |
             VerificationObligationAlreadyClaimedError |
             VerificationObligationPolicyStaleError |
             VerificationObligationUnclaimedError |
             VerificationObligationClaimStaleError |
             VerificationObligationClaimNotOwnedError |
             VerificationObligationClaimExpiredError |
             VerificationObligationBindingStaleError |
             VerificationEvidenceKindNotRequiredError |
             VerificationEvidenceAlreadySubmittedError |
             VerificationEvidenceLimitReachedError |
             VerificationObligationTerminalError |
             MergeSnapshotExistingError |
             MergeSnapshotCandidateError |
             MergeSnapshotStateError |
             MergeSnapshotVerificationBindingStaleError |
             MergeSnapshotVerificationAlreadySubmittedError |
             MergeSnapshotVerificationLimitReachedError

      ERROR_TYPES = constants(false).filter_map do |constant_name|
        candidate = const_get(constant_name)
        candidate if candidate.is_a?(Class) && candidate < Value && candidate.name.end_with?("Error")
      end.sort_by(&:name).freeze
      Type = ERROR_TYPES.reduce { _1 | _2 }
      ERROR_CODES = ERROR_TYPES.flat_map do |error_type|
        error_type.schema.key(:code).type.values
      end.map(&:to_sym).uniq.sort.freeze
    end
  end
end
