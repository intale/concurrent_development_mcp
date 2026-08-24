# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordMergeObservation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :merge_snapshot_id, Types::Identifier
      attribute :authorization_event, EventReference
      attribute :authorization_decision_digest, Types::Sha256Digest
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_before_commit_oid, Types::GitOid
      attribute :target_after_commit_oid, Types::GitOid
      attribute :observer, MergeObservations::ObserverV1
      attribute :run_id, Types::Identifier
      attribute :observed_at, Types::Timestamp
      attribute :policy_version, Types::MergeObservationPolicyVersion
    end
  end
end
