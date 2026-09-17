# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module PostRemodelCommandInputDocuments
      class LegacyResourceLeaseTargetV1 < Value
        attribute :resource_id, Types::ResourceId
        attribute :base_blob_oid, Types::GitOid.optional
        attribute? :mode, Types::WorkIntentionMode.optional
        attribute? :purpose, Types::WorkIntentionPurpose.optional
        attribute? :context, Types::WorkIntentionContext.optional
      end

      class LegacyResourceLeaseReferenceV1 < Value
        attribute :resource_id, Types::ResourceId
        attribute :lease_id, Types::UuidV7
        attribute :fencing_token, Types::FencingToken
      end

      class LegacyReserveWriteSetInputV1 < Value
        Resource = LegacyResourceLeaseTargetV1

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :base_commit_oid, Types::GitOid
        attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
        attribute :lease_duration_seconds, Types::LeaseDurationSeconds
      end

      class LegacyReserveWriteSetV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("write_set_reserve")
        attribute :input, LegacyReserveWriteSetInputV1
      end

      class LegacyExpandWriteSetInputV1 < Value
        Resource = LegacyResourceLeaseTargetV1

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :lease_set_id, Types::UuidV7
        attribute :repository_id, Types::RepositoryId
        attribute :base_commit_oid, Types::GitOid
        attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      end

      class LegacyExpandWriteSetV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("write_set_expand")
        attribute :input, LegacyExpandWriteSetInputV1
      end

      class LegacyRenewLeaseSetInputV1 < Value
        Reference = LegacyResourceLeaseReferenceV1

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :lease_set_id, Types::UuidV7
        attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
        attribute :lease_duration_seconds, Types::LeaseDurationSeconds
      end

      class LegacyRenewLeaseSetV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("lease_renew")
        attribute :input, LegacyRenewLeaseSetInputV1
      end

      class LegacyReleaseLeaseSetInputV1 < Value
        Reference = LegacyResourceLeaseReferenceV1

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :lease_set_id, Types::UuidV7
        attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      end

      class LegacyReleaseLeaseSetV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("lease_release")
        attribute :input, LegacyReleaseLeaseSetInputV1
      end

      class LegacyCandidateLeaseObservationV1 < Value
        attribute :resource_id, Types::ResourceId
        attribute :lease_id, Types::UuidV7
        attribute :fencing_token, Types::FencingToken
      end

      class LegacySubmitCandidateInputV1 < Value
        Lease = LegacyCandidateLeaseObservationV1
        Resource = CommandInputDocuments::CandidateActualResourceV2

        attribute :actor, CommandInputDocuments::ActorV1
        attribute :candidate_id, Types::Identifier
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :target_branch, Types::CandidateTargetBranch
        attribute :object_format, Types::GitObjectFormat
        attribute :base_commit_oid, Types::GitOid
        attribute :head_commit_oid, Types::GitOid
        attribute :checkpoint_kind, Types::CandidateCheckpointKind
        attribute :lease_set_id, Types::UuidV7
        attribute :leases, Types::Array.of(Lease).constrained(min_size: 1, max_size: 32)
        attribute :change_manifest, CommandInputDocuments::CandidateChangeManifestV1
        attribute :build_context, CommandInputDocuments::CandidateBuildContextV1.optional
        attribute :actual_resources,
                  Types::Array.of(Resource).constrained(
                    min_size: 1,
                    max_size: Types::CANDIDATE_ACTUAL_RESOURCE_MAXIMUM_COUNT
                  )
      end

      class LegacySubmitCandidateV1 < CommandInputDocuments::BaseV1
        attribute :tool_name, Types::String.enum("candidate_submit")
        attribute :input, LegacySubmitCandidateInputV1
      end

      SOURCE_TYPES = [
        *CommandInputDocuments::TARGET_TYPES,
        LegacyReserveWriteSetV1,
        LegacyExpandWriteSetV1,
        LegacyRenewLeaseSetV1,
        LegacyReleaseLeaseSetV1,
        LegacySubmitCandidateV1
      ].freeze
      Type = SOURCE_TYPES.reduce { _1 | _2 }
    end
  end
end
