# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectResourcesV1 < Coordinator::Shared::Value
    class Project < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :scope, Coordinator::Shared::Types::String
      attribute :display_name, Coordinator::Shared::Types::String.optional
    end

    class Resource < Coordinator::Shared::Value
      attribute :resource_id, Coordinator::Shared::Types::UuidV7
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :kind, Coordinator::Shared::Types::String.enum("file", "directory")
      attribute :path, Coordinator::Shared::Types::String
      attribute :lifecycle_status,
                Coordinator::Shared::Types::String.enum("registered", "current", "inactive")
      attribute :unbinding_reason, Coordinator::Shared::Types::String.optional
      attribute :registered_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :last_transition_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class ActiveLease < Coordinator::Shared::Value
      attribute :lease_id, Coordinator::Shared::Types::UuidV7
      attribute :lease_set_id, Coordinator::Shared::Types::UuidV7
      attribute :resource_id, Coordinator::Shared::Types::UuidV7
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :resource_kind, Coordinator::Shared::Types::String.enum("file", "directory")
      attribute :resource_path, Coordinator::Shared::Types::String
      attribute :resource_lifecycle_status, Coordinator::Shared::Types::String.optional
      attribute :base_blob_oid, Coordinator::Shared::Types::String.optional
      attribute :fencing_token, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :policy_version, Coordinator::Shared::Types::String
      attribute :change_set_id, Coordinator::Shared::Types::String
      attribute :work_item_id, Coordinator::Shared::Types::String
      attribute :attempt_id, Coordinator::Shared::Types::String
      attribute :agent_id, Coordinator::Shared::Types::String
      attribute :reserved_event_id, Coordinator::Shared::Types::UuidV7
      attribute :last_expanded_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :last_renewed_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :reserved_at, Coordinator::Shared::Types::Timestamp
      attribute :last_expanded_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :last_renewed_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :previous_expires_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :expires_at, Coordinator::Shared::Types::Timestamp
      attribute :last_projected_at, Coordinator::Shared::Types::Timestamp
    end

    class ResourcePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(Resource).constrained(max_size: 100)
      attribute :next_resource_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class ActiveLeasePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(ActiveLease).constrained(max_size: 100)
      attribute :next_lease_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    attribute :project, Project
    attribute :resources, ResourcePage
    attribute :active_leases, ActiveLeasePage
    attribute :lease_as_of, Coordinator::Shared::Types::Timestamp
  end
end
