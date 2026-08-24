# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RegisterMergeSnapshot < Value
      Candidate = Types.Instance(MergeSnapshots::RequestedCandidateV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :merge_snapshot_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :target_base_commit_oid, Types::GitOid
      attribute :ordered_candidates,
                Types::Array.of(Candidate)
                  .constrained(min_size: 1, max_size: Types::MERGE_SNAPSHOT_MAXIMUM_CANDIDATES)
      attribute :merge_commit_oid, Types::GitOid
      attribute :producer, MergeSnapshots::ProducerV1
      attribute :run_id, Types::Identifier
      attribute :produced_at, Types::Timestamp
      attribute :policy_version, Types::MergeSnapshotRegistrationPolicyVersion
    end
  end
end
