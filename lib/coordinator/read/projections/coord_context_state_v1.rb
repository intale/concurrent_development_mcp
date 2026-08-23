# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextStateV1 < Value
      class ChangeSet < Value
        attribute :change_set_id, Types::Identifier
        attribute :goal, Types::Goal
        attribute :acceptance_criteria, Types::StateAcceptanceCriteria
        attribute :status, Types::String.enum("planning", "active")
        attribute :created_at, Types::Timestamp
        attribute :activated_at, Types::Timestamp.optional
      end

      class WorkItem < Value
        attribute :work_item_id, Types::Identifier
        attribute :change_set_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :goal, Types::Goal
        attribute :acceptance_criteria, Types::WorkItemStateAcceptanceCriteria
        attribute :competitive_mode, Types::Strict::Bool
        attribute :status, Types::String.enum("planned", "ready", "acquired")
        attribute :active_attempt_id, Types::Identifier.optional
        attribute :active_agent_id, Types::Identifier.optional
        attribute :created_at, Types::Timestamp
        attribute :made_ready_at, Types::Timestamp.optional
        attribute :acquired_at, Types::Timestamp.optional
      end

      class Dependency < Value
        attribute :dependency_id, Types::Identifier
        attribute :producer_work_item_id, Types::Identifier
        attribute :consumer_work_item_id, Types::Identifier
        attribute :dependency_kind, Types::DependencyKind
        attribute :required_output, Coordinator::Write::RequiredOutput.optional
        attribute :declared_at, Types::Timestamp
      end

      class WriteSetResource < Value
        attribute :lease_id, Types::UuidV7
        attribute :resource_key, Types::String
        attribute :resource_key_hash, Types::Sha256Digest
        attribute :resource_kind, Types::ResourceKind
        attribute :resource_path, Types::ResourcePath
        attribute :base_blob_oid, Types::GitOid.optional
        attribute :fencing_token, Types::FencingToken
      end

      class WriteSet < Value
        Resource = WriteSetResource

        attribute :lease_set_id, Types::UuidV7
        attribute :repository_id, Types::RepositoryId
        attribute :policy_version, Types::String.enum(Coordinator::Write::ResourceKeyDocumentV1::POLICY_VERSION)
        attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
        attribute :reserved_at, Types::Timestamp
        attribute :last_expanded_at, Types::Timestamp.optional
        attribute :last_renewed_at, Types::Timestamp.optional
        attribute :previous_expires_at, Types::Timestamp.optional
        attribute :expires_at, Types::Timestamp
        attribute :released_at, Types::Timestamp.optional
      end

      class Attempt < Value
        attribute :attempt_id, Types::Identifier
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :agent_id, Types::Identifier
        attribute :base_snapshots, Types::Array.of(Coordinator::Write::RepositorySnapshotV1).constrained(size: 1)
        attribute :status, Types::String.enum("authorized", "started")
        attribute :authorized_at, Types::Timestamp
        attribute :started_at, Types::Timestamp.optional
        attribute :write_set, WriteSet.optional
      end

      class CandidateCheckpoint < Value
        attribute :candidate_id, Types::Identifier
        attribute :candidate_event, Coordinator::Write::EventReference
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :target_branch, Types::CandidateTargetBranch
        attribute :object_format, Types::GitObjectFormat
        attribute :base_commit_oid, Types::GitOid
        attribute :head_commit_oid, Types::GitOid
        attribute :checkpoint_kind, Types::CandidateCheckpointKind
        attribute :manifest_digest, Types::Sha256Digest
        attribute :build_context_digest, Types::Sha256Digest.optional
        attribute :attached_at, Types::Timestamp
      end

      attribute :schema, Types::String.enum("coord-context/v1")
      attribute :change_set, ChangeSet.optional
      attribute :work_item_ids, Types::WorkItemIds
      attribute :work_items, Types::Array.of(WorkItem).constrained(max_size: 100)
      attribute :dependencies, Types::Array.of(Dependency).constrained(max_size: 500)
      attribute :attempts, Types::Array.of(Attempt).constrained(max_size: 100)
      attribute :candidate_checkpoints,
                Types::Array.of(CandidateCheckpoint).constrained(max_size: 100)

      def self.initial
        new(
          schema: "coord-context/v1",
          change_set: nil,
          work_item_ids: [],
          work_items: [],
          dependencies: [],
          attempts: [],
          candidate_checkpoints: []
        )
      end
    end
  end
end
