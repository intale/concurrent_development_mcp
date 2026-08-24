# frozen_string_literal: true

module Coordinator::Write
  module MergeObservations
    class ObservationDocumentV1 < Value
      attribute :schema, Types::String.enum("merge-observation/v1")
      attribute :merge_snapshot_id, Types::Identifier
      attribute :authorization_event, EventReference
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :snapshot_binding, MergeAuthorizations::SnapshotBindingV1
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_before_commit_oid, Types::GitOid
      attribute :target_after_commit_oid, Types::GitOid
      attribute :observer, ObserverV1
      attribute :run_id, Types::Identifier
      attribute :observed_at, Types::Timestamp
      attribute :policy_version, Types::MergeObservationPolicyVersion
    end
  end
end
