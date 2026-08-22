# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class State < Value
        Snapshot = Types.Instance(RepositorySnapshotV1)
        LeaseReference = Types.Instance(LeaseReferenceV1)

        attribute :attempt_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 1)
        attribute :lease_set_id, Types::UuidV7.optional
        attribute :lease_repository_id, Types::RepositoryId.optional
        attribute :lease_policy_version, Types::String.optional
        attribute :lease_resources, Types::Array.of(LeaseReference).constrained(max_size: 32)
        attribute :lease_reserved_at, Types::Timestamp.optional
        attribute :lease_renewed_at, Types::Timestamp.optional
        attribute :lease_expires_at, Types::Timestamp.optional
        attribute :lease_released_at, Types::Timestamp.optional
        attribute :status, Types::String.enum("absent", "authorized", "active")

        def self.initial
          new(
            attempt_id: nil,
            change_set_id: nil,
            work_item_id: nil,
            agent_id: nil,
            base_snapshots: [],
            lease_set_id: nil,
            lease_repository_id: nil,
            lease_policy_version: nil,
            lease_resources: [],
            lease_reserved_at: nil,
            lease_renewed_at: nil,
            lease_expires_at: nil,
            lease_released_at: nil,
            status: "absent"
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          status == "absent"
        end

        def apply(event)
          case event
          when Events::AttemptAuthorizedV1
            self.class.new(
              attempt_id: event.attempt_id,
              change_set_id: event.change_set_id,
              work_item_id: event.work_item_id,
              agent_id: event.agent_id,
              base_snapshots: event.base_snapshots,
              lease_set_id: nil,
              lease_repository_id: nil,
              lease_policy_version: nil,
              lease_resources: [],
              lease_reserved_at: nil,
              lease_renewed_at: nil,
              lease_expires_at: nil,
              lease_released_at: nil,
              status: "authorized"
            )
          when Events::AttemptStartedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id:,
              lease_repository_id:,
              lease_policy_version:,
              lease_resources:,
              lease_reserved_at:,
              lease_renewed_at:,
              lease_expires_at:,
              lease_released_at:,
              status: "active"
            )
          when Events::WriteSetReservedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              lease_repository_id: event.repository_id,
              lease_policy_version: event.policy_version,
              lease_resources: event.resources,
              lease_reserved_at: event.reserved_at,
              lease_renewed_at: nil,
              lease_expires_at: event.expires_at,
              lease_released_at: nil,
              status:
            )
          when Events::WriteSetExpandedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              lease_repository_id: event.repository_id,
              lease_policy_version: event.policy_version,
              lease_resources: (lease_resources + event.added_resources).sort_by(&:resource_key_hash),
              lease_reserved_at:,
              lease_renewed_at:,
              lease_expires_at: event.expires_at,
              lease_released_at:,
              status:
            )
          when Events::WriteSetRenewedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              lease_repository_id: event.repository_id,
              lease_policy_version: event.policy_version,
              lease_resources: event.resources,
              lease_reserved_at:,
              lease_renewed_at: event.renewed_at,
              lease_expires_at: event.expires_at,
              lease_released_at:,
              status:
            )
          when Events::WriteSetReleasedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              lease_repository_id: event.repository_id,
              lease_policy_version: event.policy_version,
              lease_resources: event.resources,
              lease_reserved_at:,
              lease_renewed_at:,
              lease_expires_at: event.previous_expires_at,
              lease_released_at: event.released_at,
              status:
            )
          else
            self
          end
        end
      end
    end
  end
end
