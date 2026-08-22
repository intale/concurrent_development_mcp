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
             SourceSpanMismatchError |
             TopicNotSupportedError |
             TopicValueInvalidError
    end
  end
end
