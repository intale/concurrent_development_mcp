# frozen_string_literal: true

module Coordinator::Write
  module CommandInputDocuments
    class ActorV1 < Value
      attribute :actor_kind, Types::ActorKind
      attribute :actor_id, Types::Identifier
    end

    class BaseV1 < Value
      attribute :schema, Types::String.enum("command-input/v1")
      attribute :command_id, Types::Identifier
    end

    class CreateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::AcceptanceCriteria
    end

    class CreateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_create")
      attribute :input, CreateChangeSetInputV1
    end

    class CreateWorkItemInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :goal, Types::Goal
      attribute :acceptance_criteria, Types::WorkItemAcceptanceCriteria
    end

    class CreateWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_create")
      attribute :input, CreateWorkItemInputV1
    end

    class DeclareWorkItemDependencyInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
    end

    class DeclareWorkItemDependencyV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_dependency_declare")
      attribute :input, DeclareWorkItemDependencyInputV1
    end

    class ActivateChangeSetInputV1 < Value
      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
    end

    class ActivateChangeSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("change_set_activate")
      attribute :input, ActivateChangeSetInputV1
    end

    class RepositorySnapshotV1 < Value
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :commit_oid, Types::GitOid
    end

    class AcquireWorkItemInputV1 < Value
      Snapshot = RepositorySnapshotV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 100)
    end

    class AcquireWorkItemV1 < BaseV1
      attribute :tool_name, Types::String.enum("work_item_acquire")
      attribute :input, AcquireWorkItemInputV1
    end

    class FileResourceV1 < Value
      attribute :kind, Types::ResourceKind
      attribute :path, Types::ResourcePath
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :resource_key, Types::String
      attribute :resource_key_hash, Types::Sha256Digest
      attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
    end

    class ReserveWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
      attribute :lease_duration_seconds, Types::LeaseDurationSeconds
    end

    class ReserveWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_reserve")
      attribute :input, ReserveWriteSetInputV1
    end

    class ExpandWriteSetInputV1 < Value
      Resource = FileResourceV1

      attribute :actor, ActorV1
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :repository_id, Types::RepositoryId
      attribute :base_commit_oid, Types::GitOid
      attribute :resources, Types::Array.of(Resource).constrained(min_size: 1, max_size: 32)
    end

    class ExpandWriteSetV1 < BaseV1
      attribute :tool_name, Types::String.enum("write_set_expand")
      attribute :input, ExpandWriteSetInputV1
    end

    Type = CreateChangeSetV1 |
           CreateWorkItemV1 |
           DeclareWorkItemDependencyV1 |
           ActivateChangeSetV1 |
           AcquireWorkItemV1 |
           ReserveWriteSetV1 |
           ExpandWriteSetV1
  end
end
