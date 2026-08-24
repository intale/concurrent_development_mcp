# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class TargetBaseObservationV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :commit_oid, Types::GitOid
      attribute :observer, MergeSnapshotVerifications::ProducerV1
      attribute :run_id, Types::Identifier
      attribute :observed_at, Types::Timestamp
    end
  end
end
