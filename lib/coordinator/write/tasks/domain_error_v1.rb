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

      class WriteSetLimitDetails < AttemptDetails
        attribute :current_resource_count, Types::WriteSetSize
        attribute :requested_addition_count, Types::WriteSetSize
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

      class WriteSetLimitError < Value
        attribute :code, Types::String.enum("write_set_limit_reached")
        attribute :message, Types::String
        attribute :details, WriteSetLimitDetails
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

      Type = ChangeSetError |
             ActivationDependencyError |
             WorkItemError |
             DependencyError |
             AttemptError |
             CommandIdReusedError |
             LeaseBusyError |
             LeaseSetMismatchError |
             ResourceEvidenceConflictError |
             WriteSetLimitError |
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
             VerificationObligationNotFoundError |
             VerificationObligationAlreadyClaimedError
    end
  end
end
