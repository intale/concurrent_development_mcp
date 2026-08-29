# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceBoundaryEpochRolledV2 < Base
      class ActiveLeaseV2 < Value
        attribute :lease_id, Types::UuidV7
        attribute :lease_set_id, Types::UuidV7
        attribute :resource_id, Types::ResourceId
        attribute :resource_kind, Types::ResourceKind
        attribute :resource_path, Types::ResourcePath
        attribute :policy_version, Types::String.enum(LeaseResourceV2::POLICY_VERSION)
        attribute :mode, Types::LeaseMode
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
        attribute :agent_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :object_format, Types::GitObjectFormat
        attribute :base_commit_oid, Types::GitOid
        attribute :base_blob_oid, Types::GitOid.optional
        attribute :fencing_token, Types::FencingToken
        attribute :acquired_at, Types::Timestamp
        attribute :renewed_at, Types::Timestamp.optional
        attribute :expires_at, Types::Timestamp

        def self.from_state(state)
          new(
            lease_id: state.lease_id,
            lease_set_id: state.lease_set_id,
            resource_id: state.resource_id,
            resource_kind: state.resource_kind,
            resource_path: state.resource_path,
            policy_version: state.policy_version,
            mode: state.mode,
            change_set_id: state.change_set_id,
            work_item_id: state.work_item_id,
            attempt_id: state.attempt_id,
            agent_id: state.agent_id,
            repository_id: state.repository_id,
            object_format: state.object_format,
            base_commit_oid: state.base_commit_oid,
            base_blob_oid: state.base_blob_oid,
            fencing_token: state.fencing_token,
            acquired_at: state.acquired_at,
            renewed_at: state.renewed_at,
            expires_at: state.expires_at
          )
        end

        def to_state
          Domain::ResourceLeases::State.new(
            **to_h,
            resource_key: nil,
            resource_key_hash: nil,
            released_at: nil,
            expired_at: nil
          )
        end
      end

      ActiveLease = ActiveLeaseV2

      contract type: "ResourceBoundaryEpochRolled", version: 2

      attribute :repository_id, Types::RepositoryId
      attribute :boundary_marker, Types::Marker
      attribute :epoch, Types::Integer.constrained(gteq: 1)
      attribute :previous_through_global_position, Types::GlobalPosition.optional
      attribute :through_global_position, Types::GlobalPosition
      attribute :active_leases,
                Types::Array.of(ActiveLease).constrained(
                  max_size: EventQueries::RESOURCE_BOUNDARY_ACTIVE_LEASE_MAXIMUM_COUNT
                )
      attribute :rolled_at, Types::Timestamp
    end
  end
end
