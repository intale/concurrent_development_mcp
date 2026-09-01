# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  module DeliveryTypes
    class DeliverySortEnum < BaseEnum
      graphql_name "DeliverySort"
      value "NEWEST_FIRST", value: "newest_first"
      value "OLDEST_FIRST", value: "oldest_first"
    end

    class CandidateCheckpointKindEnum < BaseEnum
      graphql_name "CandidateCheckpointKind"
      value "INTERMEDIATE", value: "intermediate"
      value "HANDOFF", value: "handoff"
      value "FINAL", value: "final"
    end

    class CandidateImpactDirectionEnum < BaseEnum
      graphql_name "CandidateImpactDirection"
      value "INCOMING", value: "incoming"
      value "OUTGOING", value: "outgoing"
    end

    class VerificationObligationStatusEnum < BaseEnum
      graphql_name "VerificationObligationStatus"
      value "OPEN", value: "open"
      value "SATISFIED", value: "satisfied"
      value "FAILED", value: "failed"
      value "WAIVED", value: "waived"
      value "INVALIDATED", value: "invalidated"
    end

    class ReleaseSetStatusEnum < BaseEnum
      graphql_name "ReleaseSetStatus"
      %w[prepared integrating verifying verified activated compensation_requested completed].each do |status|
        value status.upcase, value: status
      end
    end

    class OperationBatchStatusEnum < BaseEnum
      graphql_name "OperationBatchStatus"
      %w[running cancelling completed completed_with_errors cancelled].each do |status|
        value status.upcase, value: status
      end
    end

    class OperationBatchToolEnum < BaseEnum
      graphql_name "OperationBatchTool"
      value "SKILL_PUBLISH", value: "skill_publish"
      value "DEVELOPMENT_ARTIFACT_CAPTURE", value: "development_artifact_capture"
      value "DEVELOPMENT_ARTIFACT_RELATION_DECLARE", value: "development_artifact_relation_declare"
    end

    class OperationBatchItemStatusEnum < BaseEnum
      graphql_name "OperationBatchItemStatus"
      %w[pending not_run succeeded rejected].each { |status| value status.upcase, value: status }
    end

    class CandidateCheckpointType < BaseObject
      graphql_name "CandidateCheckpoint"
      field :base_commit_oid, String, null: false
      field :build_context_digest, String, null: true
      field :build_context_observed, Boolean, null: false
      field :change_set_id, ID, null: false
      field :checkpoint_kind, CandidateCheckpointKindEnum, null: false
      field :evidence_status, String, null: false
      field :head_commit_oid, String, null: false
      field :id, ID, null: false, method: :candidate_id
      field :manifest_digest, String, null: false
      field :manifest_observed, Boolean, null: false
      field :repository_id, ID, null: false
      field :submitted_at, String, null: false
      field :target_branch, String, null: false
      field :attempt_id, ID, null: false
      field :work_item_id, ID, null: false

      def manifest_observed
        object.respond_to?(:manifest_observed) ? object.manifest_observed : !object.manifest.nil?
      end

      def build_context_observed
        object.respond_to?(:build_context_observed) ? object.build_context_observed : !object.build_context.nil?
      end

      def submitted_at
        object.submitted.occurred_at
      end
    end

    class CandidateCheckpointConnectionType < BaseObject
      graphql_name "CandidateCheckpointConnection"
      field :nodes, [ CandidateCheckpointType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class VerificationObligationType < BaseObject
      graphql_name "DeliveryVerificationObligation"
      field :change_set_id, ID, null: false
      field :claim_expires_at, String, null: true
      field :claimant_id, ID, null: true
      field :created_at, String, null: false
      field :enforcement, String, null: false
      field :evidence_count, Integer, null: false
      field :id, ID, null: false, method: :obligation_id
      field :kind, String, null: false
      field :missing_evidence_kinds, [ String ], null: false
      field :passed_evidence_kinds, [ String ], null: false
      field :source_candidate_id, ID, null: false
      field :source_repository_id, ID, null: false
      field :status, VerificationObligationStatusEnum, null: false
      field :target_candidate_id, ID, null: false
      field :target_repository_id, ID, null: false
    end

    class VerificationObligationConnectionType < BaseObject
      graphql_name "VerificationObligationConnection"
      field :nodes, [ VerificationObligationType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class VerificationReasonType < BaseObject
      graphql_name "VerificationReason"
      field :kind, String, null: false
      field :matches, [ String ], null: false
    end

    class VerificationEvidenceType < BaseObject
      graphql_name "VerificationEvidence"
      field :assessment_input_digest, String, null: false
      field :conclusion, String, null: false
      field :evidence_kind, String, null: false
      field :global_position, GraphQL::Types::BigInt, null: false
      field :id, ID, null: false, method: :evidence_id
      field :produced_at, String, null: false
      field :result_digest, String, null: false
      field :submitted_at, String, null: false
    end

    class VerificationEvidenceConnectionType < BaseObject
      graphql_name "VerificationEvidenceConnection"
      field :nodes, [ VerificationEvidenceType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class ProjectVerificationObligationType < BaseObject
      graphql_name "ProjectVerificationObligation"
      field :evidence, VerificationEvidenceConnectionType, null: false, connection: false
      field :obligation, VerificationObligationType, null: false
      field :project, CoordinationProjectType, null: false
      field :reasons, [ VerificationReasonType ], null: false
      field :required_evidence, [ String ], null: false
    end

    class MergeSnapshotType < BaseObject
      graphql_name "DeliveryMergeSnapshot"
      field :candidate_count, Integer, null: false
      field :evidence_status, String, null: false
      field :id, ID, null: false, method: :merge_snapshot_id
      field :merge_commit_oid, String, null: false
      field :produced_at, String, null: false
      field :repository_id, ID, null: false
      field :target_base_commit_oid, String, null: false
      field :target_branch, String, null: false
      field :verification_status, String, null: false
    end

    class MergeSnapshotConnectionType < BaseObject
      graphql_name "MergeSnapshotConnection"
      field :nodes, [ MergeSnapshotType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class MergeCandidateType < BaseObject
      graphql_name "MergeCandidate"
      field :attempt_id, ID, null: false
      field :base_commit_oid, String, null: false
      field :change_set_id, ID, null: false
      field :head_commit_oid, String, null: false
      field :id, ID, null: false, method: :candidate_id
      field :manifest_digest, String, null: false
      field :work_item_id, ID, null: false
    end

    class MergeAuthorizationType < BaseObject
      graphql_name "MergeAuthorization"
      field :decided_at, String, null: false
      field :decision_digest, String, null: false
      field :id, ID, null: false, method: :authorization_id
      field :input_digest, String, null: false
      field :merge_snapshot_id, ID, null: false
      field :outcome, String, null: false
      field :policy_version, String, null: false
      field :reason_count, Integer, null: false
    end

    class MergeAuthorizationConnectionType < BaseObject
      graphql_name "MergeAuthorizationConnection"
      field :nodes, [ MergeAuthorizationType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class ProjectMergeSnapshotType < BaseObject
      graphql_name "ProjectMergeSnapshot"
      field :authorizations, MergeAuthorizationConnectionType, null: false, connection: false
      field :candidates, [ MergeCandidateType ], null: false
      field :project, CoordinationProjectType, null: false
      field :snapshot, MergeSnapshotType, null: false
    end

    class ReleaseSetType < BaseObject
      graphql_name "DeliveryReleaseSet"
      field :change_set_id, ID, null: false
      field :id, ID, null: false, method: :release_set_id
      field :member_count, Integer, null: false
      field :prepared_at, String, null: false
      field :release_digest, String, null: false
      field :repository_ids, [ ID ], null: false
      field :status, ReleaseSetStatusEnum, null: false
      field :verification_status, String, null: false
    end

    class ReleaseSetConnectionType < BaseObject
      graphql_name "ReleaseSetConnection"
      field :nodes, [ ReleaseSetType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class ReleaseMemberType < BaseObject
      graphql_name "ReleaseMember"
      field :candidate_count, Integer, null: false
      field :change_set_id, ID, null: false
      field :merge_commit_oid, String, null: false
      field :merge_snapshot_id, ID, null: false
      field :position, Integer, null: false
      field :repository_id, ID, null: false
      field :target_branch, String, null: false
    end

    class ReleaseIntegrationType < BaseObject
      graphql_name "ReleaseIntegration"
      field :attempt_id, ID, null: false
      field :attempt_number, Integer, null: false
      field :failure_code, String, null: true
      field :outcome, String, null: false
      field :recorded_at, String, null: false
      field :repository_id, ID, null: false
    end

    class ProjectReleaseSetType < BaseObject
      graphql_name "ProjectReleaseSet"
      field :activated, Boolean, null: false
      field :compensation_requested, Boolean, null: false
      field :completion_outcome, String, null: true
      field :integrations, [ ReleaseIntegrationType ], null: false
      field :members, [ ReleaseMemberType ], null: false
      field :project, CoordinationProjectType, null: false
      field :release_set, ReleaseSetType, null: false
      field :verification_attempt_count, Integer, null: false
    end

    class CandidateImpactReasonType < BaseObject
      graphql_name "CandidateImpactReason"
      field :kind, String, null: false
      field :matches, [ String ], null: false
    end

    class CandidateImpactRelationshipType < BaseObject
      graphql_name "CandidateImpactRelationship"
      field :counterpart, CandidateCheckpointType, null: false
      field :reasons, [ CandidateImpactReasonType ], null: false
      field :relationship_kind, String, null: false
    end

    class CandidateImpactConnectionType < BaseObject
      graphql_name "CandidateImpactConnection"
      field :nodes, [ CandidateImpactRelationshipType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class ProjectCandidateCheckpointType < BaseObject
      graphql_name "ProjectCandidateCheckpoint"
      field :checkpoint, CandidateCheckpointType, null: false
      field :impact_direction, CandidateImpactDirectionEnum, null: false
      field :impact_relationships, CandidateImpactConnectionType, null: false, connection: false
      field :impact_surface_digest, String, null: true
      field :project, CoordinationProjectType, null: false
    end

    class ProjectDeliveryType < BaseObject
      graphql_name "ProjectDelivery"
      field :candidates, CandidateCheckpointConnectionType, null: false, connection: false
      field :merge_snapshots, MergeSnapshotConnectionType, null: false, connection: false
      field :obligations, VerificationObligationConnectionType, null: false, connection: false
      field :project, CoordinationProjectType, null: false
      field :release_sets, ReleaseSetConnectionType, null: false, connection: false
    end

    class OperationBatchType < BaseObject
      graphql_name "DeliveryOperationBatch"
      field :created_at, String, null: false
      field :id, ID, null: false, method: :batch_id
      field :manifest_digest, String, null: false
      field :not_run, Integer, null: false
      field :pending, Integer, null: false
      field :rejected, Integer, null: false
      field :status, OperationBatchStatusEnum, null: false
      field :succeeded, Integer, null: false
      field :target_tool, OperationBatchToolEnum, null: false
      field :total, Integer, null: false
    end

    class OperationBatchConnectionType < BaseObject
      graphql_name "OperationBatchConnection"
      field :nodes, [ OperationBatchType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class OperationBatchItemType < BaseObject
      graphql_name "DeliveryOperationBatchItem"
      field :canonical_input_digest, String, null: false
      field :command_id, ID, null: false
      field :finished_at, String, null: true
      field :index, Integer, null: false
      field :outcome_code, String, null: true
      field :outcome_status, String, null: true
      field :outcome_summary, String, null: true
      field :status, OperationBatchItemStatusEnum, null: false
      field :target_tool, OperationBatchToolEnum, null: false
    end

    class OperationBatchItemConnectionType < BaseObject
      graphql_name "OperationBatchItemConnection"
      field :nodes, [ OperationBatchItemType ], null: false
      field :page_info, PageInfoType, null: false
    end

    class OperationBatchDetailType < BaseObject
      graphql_name "OperationBatchDetail"
      field :batch, OperationBatchType, null: false
      field :items, OperationBatchItemConnectionType, null: false, connection: false
    end
  end
end
