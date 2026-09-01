# frozen_string_literal: true

module Coordinator::Read::Web
  class DeliveryBrowserV1
    class TimelineCursor < Coordinator::Shared::Value
      attribute :position, Coordinator::Shared::Types::GlobalPosition
      attribute :id, Coordinator::Shared::Types::Identifier
    end

    class CandidatePage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(Coordinator::Read::CandidateSummaryV1)
                  .constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class VerificationSummary < Coordinator::Shared::Value
      attribute :obligation_id, Coordinator::Shared::Types::Identifier
      attribute :kind, Coordinator::Shared::Types::VerificationObligationKind
      attribute :status, Coordinator::Shared::Types::VerificationObligationStatus
      attribute :change_set_id, Coordinator::Shared::Types::Identifier
      attribute :source_candidate_id, Coordinator::Shared::Types::Identifier
      attribute :target_candidate_id, Coordinator::Shared::Types::Identifier
      attribute :source_repository_id, Coordinator::Shared::Types::UuidV7
      attribute :target_repository_id, Coordinator::Shared::Types::UuidV7
      attribute :enforcement, Coordinator::Shared::Types::String.enum("verification_gate", "merge_gate")
      attribute :claimant_id, Coordinator::Shared::Types::Identifier.optional
      attribute :claim_expires_at, Coordinator::Shared::Types::String.optional
      attribute :evidence_count, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :passed_evidence_kinds, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
      attribute :missing_evidence_kinds, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
      attribute :created_at, Coordinator::Shared::Types::String
    end

    class VerificationPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(VerificationSummary).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class VerificationReason < Coordinator::Shared::Value
      attribute :kind, Coordinator::Shared::Types::String
      attribute :matches, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
    end

    class VerificationEvidence < Coordinator::Shared::Value
      attribute :evidence_id, Coordinator::Shared::Types::UuidV7
      attribute :evidence_kind, Coordinator::Shared::Types::String
      attribute :conclusion, Coordinator::Shared::Types::String
      attribute :assessment_input_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :result_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :produced_at, Coordinator::Shared::Types::String
      attribute :submitted_at, Coordinator::Shared::Types::String
      attribute :global_position, Coordinator::Shared::Types::GlobalPosition
    end

    class EvidencePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(VerificationEvidence).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class MergeSummary < Coordinator::Shared::Value
      attribute :merge_snapshot_id, Coordinator::Shared::Types::Identifier
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :target_branch, Coordinator::Shared::Types::String
      attribute :target_base_commit_oid, Coordinator::Shared::Types::GitOid
      attribute :merge_commit_oid, Coordinator::Shared::Types::GitOid
      attribute :candidate_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :verification_status, Coordinator::Shared::Types::MergeSnapshotVerificationStatus
      attribute :evidence_status, Coordinator::Shared::Types::MergeSnapshotEvidenceStatus
      attribute :produced_at, Coordinator::Shared::Types::String
    end

    class MergePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(MergeSummary).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class AuthorizationSummary < Coordinator::Shared::Value
      attribute :authorization_id, Coordinator::Shared::Types::UuidV7
      attribute :merge_snapshot_id, Coordinator::Shared::Types::Identifier
      attribute :outcome, Coordinator::Shared::Types::String.enum("granted", "denied")
      attribute :policy_version, Coordinator::Shared::Types::String
      attribute :input_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :decision_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :reason_count, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :decided_at, Coordinator::Shared::Types::String
    end

    class AuthorizationPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(AuthorizationSummary).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class MergeCandidate < Coordinator::Shared::Value
      attribute :candidate_id, Coordinator::Shared::Types::Identifier
      attribute :change_set_id, Coordinator::Shared::Types::Identifier
      attribute :work_item_id, Coordinator::Shared::Types::Identifier
      attribute :attempt_id, Coordinator::Shared::Types::Identifier
      attribute :base_commit_oid, Coordinator::Shared::Types::GitOid
      attribute :head_commit_oid, Coordinator::Shared::Types::GitOid
      attribute :manifest_digest, Coordinator::Shared::Types::Sha256Digest
    end

    class ReleaseSummary < Coordinator::Shared::Value
      attribute :release_set_id, Coordinator::Shared::Types::Identifier
      attribute :change_set_id, Coordinator::Shared::Types::Identifier
      attribute :repository_ids, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::UuidV7)
      attribute :member_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :status, Coordinator::Shared::Types::String
      attribute :verification_status, Coordinator::Shared::Types::String
      attribute :release_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :prepared_at, Coordinator::Shared::Types::String
    end

    class ReleasePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(ReleaseSummary).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class ReleaseMember < Coordinator::Shared::Value
      attribute :position, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :target_branch, Coordinator::Shared::Types::String
      attribute :merge_snapshot_id, Coordinator::Shared::Types::Identifier
      attribute :change_set_id, Coordinator::Shared::Types::Identifier
      attribute :merge_commit_oid, Coordinator::Shared::Types::GitOid
      attribute :candidate_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
    end

    class ReleaseIntegration < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :attempt_id, Coordinator::Shared::Types::Identifier
      attribute :attempt_number, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :outcome, Coordinator::Shared::Types::String
      attribute :failure_code, Coordinator::Shared::Types::String.optional
      attribute :recorded_at, Coordinator::Shared::Types::String
    end

    class OperationBatchSummary < Coordinator::Shared::Value
      attribute :batch_id, Coordinator::Shared::Types::UuidV7
      attribute :target_tool, Coordinator::Shared::Types::OperationBatchTargetTool
      attribute :status, Coordinator::Shared::Types::OperationBatchStatus
      attribute :total, Coordinator::Shared::Types::OperationBatchTotal
      attribute :succeeded, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :rejected, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :pending, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :not_run, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :manifest_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :created_at, Coordinator::Shared::Types::String
    end

    class OperationBatchPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(OperationBatchSummary).constrained(max_size: 50)
      attribute :next_cursor, TimelineCursor.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class OperationBatchItem < Coordinator::Shared::Value
      attribute :index, Coordinator::Shared::Types::OperationBatchItemIndex
      attribute :target_tool, Coordinator::Shared::Types::OperationBatchTargetTool
      attribute :command_id, Coordinator::Shared::Types::Identifier
      attribute :canonical_input_digest, Coordinator::Shared::Types::Sha256Digest
      attribute :status, Coordinator::Shared::Types::OperationBatchItemStatus
      attribute :outcome_status, Coordinator::Shared::Types::String.optional
      attribute :outcome_summary, Coordinator::Shared::Types::String.optional
      attribute :outcome_code, Coordinator::Shared::Types::String.optional
      attribute :finished_at, Coordinator::Shared::Types::String.optional
    end

    class OperationBatchItemPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(OperationBatchItem).constrained(max_size: 100)
      attribute :next_index, Coordinator::Shared::Types::OperationBatchItemIndex.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class CandidateDetail < Coordinator::Shared::Value
      attribute :candidate, Coordinator::Read::CandidateViewV1
      attribute :impacts, Coordinator::Read::CandidateImpactPageV1
    end

    class VerificationDetail < Coordinator::Shared::Value
      attribute :obligation, VerificationSummary
      attribute :required_evidence, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
      attribute :reasons, Coordinator::Shared::Types::Array.of(VerificationReason)
      attribute :evidence, EvidencePage
    end

    class MergeDetail < Coordinator::Shared::Value
      attribute :snapshot, MergeSummary
      attribute :candidates, Coordinator::Shared::Types::Array.of(MergeCandidate)
      attribute :authorizations, AuthorizationPage
    end

    class ReleaseDetail < Coordinator::Shared::Value
      attribute :release_set, ReleaseSummary
      attribute :members, Coordinator::Shared::Types::Array.of(ReleaseMember)
      attribute :integrations, Coordinator::Shared::Types::Array.of(ReleaseIntegration)
      attribute :verification_attempt_count, Coordinator::Shared::Types::Integer.constrained(gteq: 0)
      attribute :activated, Coordinator::Shared::Types::Strict::Bool
      attribute :compensation_requested, Coordinator::Shared::Types::Strict::Bool
      attribute :completion_outcome, Coordinator::Shared::Types::String.optional
    end

    class OperationBatchDetail < Coordinator::Shared::Value
      attribute :batch, OperationBatchSummary
      attribute :items, OperationBatchItemPage
    end
  end
end
