# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class SubmitCandidate < Value
      Lease = Types.Instance(Candidates::LeaseObservationV1)
      Resource = Types.Instance(Candidates::ActualResourceV2)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :candidate_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::UuidV7
      attribute :target_branch, Types::CandidateTargetBranch
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
      attribute :checkpoint_kind, Types::CandidateCheckpointKind
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Lease).constrained(min_size: 1, max_size: 32)
      attribute :manifest, Types.Instance(Candidates::ChangeManifestV1)
      attribute :build_context, Types.Instance(Candidates::BuildContextV1).optional
      attribute :actual_resources,
                Types::Array.of(Resource).constrained(
                  min_size: 1,
                  max_size: Types::CANDIDATE_ACTUAL_RESOURCE_MAXIMUM_COUNT
                )
    end
  end
end
