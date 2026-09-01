# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectResourcesV1
    class Resource < Coordinator::Shared::Value
      attribute :resource_id, Coordinator::Shared::Types::UuidV7
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :kind, Coordinator::Shared::Types::String.enum("file", "directory")
      attribute :path, Coordinator::Shared::Types::String
      attribute :lifecycle_status,
                Coordinator::Shared::Types::String.enum("registered", "current", "inactive")
      attribute :unbinding_reason, Coordinator::Shared::Types::String.optional
      attribute :registered_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :registered_actor_id, Coordinator::Shared::Types::String.optional
      attribute :registered_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :latest_transition_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :latest_transition_actor_id, Coordinator::Shared::Types::String.optional
      attribute :last_transition_at, Coordinator::Shared::Types::Timestamp.optional
    end

    class Lease < Coordinator::Shared::Value
      attribute :lease_id, Coordinator::Shared::Types::UuidV7
      attribute :lease_set_id, Coordinator::Shared::Types::UuidV7
      attribute :resource_id, Coordinator::Shared::Types::UuidV7
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :resource_kind, Coordinator::Shared::Types::String.enum("file", "directory")
      attribute :resource_path, Coordinator::Shared::Types::String
      attribute :resource_lifecycle_status, Coordinator::Shared::Types::String.optional
      attribute :status,
                Coordinator::Shared::Types::String.enum("active", "expired", "released", "attempt_terminal")
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
      attribute :release_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :attempt_terminal_event_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :reserved_at, Coordinator::Shared::Types::Timestamp
      attribute :last_expanded_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :last_renewed_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :previous_expires_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :expires_at, Coordinator::Shared::Types::Timestamp
      attribute :released_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :attempt_terminal_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :last_projected_at, Coordinator::Shared::Types::Timestamp
    end

    class ResourcePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(Resource).constrained(max_size: 100)
      attribute :next_resource_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class LeasePage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(Lease).constrained(max_size: 100)
      attribute :next_lease_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
      attribute :as_of, Coordinator::Shared::Types::Timestamp
    end
  end
end
