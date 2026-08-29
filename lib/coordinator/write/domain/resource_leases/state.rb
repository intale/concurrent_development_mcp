# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class State < Value
        attribute :lease_id, Types::UuidV7.optional
        attribute :lease_set_id, Types::UuidV7.optional
        attribute :resource_id, Types::ResourceId.optional
        attribute :resource_kind, Types::ResourceKind.optional
        attribute :resource_path, Types::ResourcePath.optional
        attribute :policy_version, Types::String.optional
        attribute :mode, Types::LeaseMode.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :attempt_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :repository_id, Types::RepositoryId.optional
        attribute :object_format, Types::GitObjectFormat.optional
        attribute :base_commit_oid, Types::GitOid.optional
        attribute :base_blob_oid, Types::GitOid.optional
        attribute :fencing_token, Types::Integer.constrained(gteq: 0)
        attribute :acquired_at, Types::Timestamp.optional
        attribute :renewed_at, Types::Timestamp.optional
        attribute :expires_at, Types::Timestamp.optional
        attribute :released_at, Types::Timestamp.optional
        attribute :expired_at, Types::Timestamp.optional

        def self.initial
          new(
            lease_id: nil,
            lease_set_id: nil,
            resource_id: nil,
            resource_kind: nil,
            resource_path: nil,
            policy_version: nil,
            mode: nil,
            change_set_id: nil,
            work_item_id: nil,
            attempt_id: nil,
            agent_id: nil,
            repository_id: nil,
            object_format: nil,
            base_commit_oid: nil,
            base_blob_oid: nil,
            fencing_token: 0,
            acquired_at: nil,
            renewed_at: nil,
            expires_at: nil,
            released_at: nil,
            expired_at: nil
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def active_at?(timestamp)
          !lease_id.nil? && released_at.nil? && expired_at.nil? && expires_at > timestamp
        end

        def next_fencing_token
          fencing_token + 1
        end

        def identity
          resource_id
        end

        def apply(event)
          case event
          when Events::ResourceLeaseAcquiredV2
            from_acquisition(event)
          when Events::ResourceLeaseRenewedV2
            from_renewal(event)
          when Events::ResourceLeaseReleasedV2
            from_release(event)
          when Events::ResourceLeaseExpiredV2
            from_expiration(event)
          else
            self
          end
        end

        private

        def from_acquisition(event)
          self.class.new(
            lease_id: event.lease_id,
            lease_set_id: event.lease_set_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            policy_version: event.policy_version,
            mode: event.mode,
            change_set_id: event.change_set_id,
            work_item_id: event.work_item_id,
            attempt_id: event.attempt_id,
            agent_id: event.agent_id,
            repository_id: event.repository_id,
            object_format: event.object_format,
            base_commit_oid: event.base_commit_oid,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token,
            acquired_at: event.acquired_at,
            renewed_at: nil,
            expires_at: event.expires_at,
            released_at: nil,
            expired_at: nil
          )
        end

        def from_renewal(event)
          self.class.new(
            lease_id: event.lease_id,
            lease_set_id: event.lease_set_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            policy_version: event.policy_version,
            mode: event.mode,
            change_set_id: event.change_set_id,
            work_item_id: event.work_item_id,
            attempt_id: event.attempt_id,
            agent_id: event.agent_id,
            repository_id: event.repository_id,
            object_format: event.object_format,
            base_commit_oid: event.base_commit_oid,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token,
            acquired_at:,
            renewed_at: event.renewed_at,
            expires_at: event.expires_at,
            released_at: nil,
            expired_at: nil
          )
        end

        def from_release(event)
          self.class.new(
            lease_id: event.lease_id,
            lease_set_id: event.lease_set_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            policy_version: event.policy_version,
            mode: event.mode,
            change_set_id: event.change_set_id,
            work_item_id: event.work_item_id,
            attempt_id: event.attempt_id,
            agent_id: event.agent_id,
            repository_id: event.repository_id,
            object_format: event.object_format,
            base_commit_oid: event.base_commit_oid,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token,
            acquired_at: event.acquired_at,
            renewed_at:,
            expires_at: event.previous_expires_at,
            released_at: event.released_at,
            expired_at: nil
          )
        end

        def from_expiration(event)
          self.class.new(
            lease_id: event.lease_id,
            lease_set_id: event.lease_set_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            policy_version: event.policy_version,
            mode: event.mode,
            change_set_id: event.change_set_id,
            work_item_id: event.work_item_id,
            attempt_id: event.attempt_id,
            agent_id: event.agent_id,
            repository_id: event.repository_id,
            object_format: event.object_format,
            base_commit_oid: event.base_commit_oid,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token,
            acquired_at: event.acquired_at,
            renewed_at: event.renewed_at,
            expires_at: event.expires_at,
            released_at: nil,
            expired_at: event.expired_at
          )
        end
      end
    end
  end
end
