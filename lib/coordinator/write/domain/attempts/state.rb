# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class State < Value
        Snapshot = Types.Instance(RepositorySnapshotV1)
        LeaseReference = LeaseReferenceV2

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
        attribute :status, Types::String.enum("absent", "authorized", "active", "abandoned", "completed")
        attribute :selected_candidate_id, Types::Identifier.optional.default(nil)
        attribute :selected_candidate_event, EventReference.optional.default(nil)
        attribute :selected_candidate_checkpoint_kind, Types::CandidateCheckpointKind.optional.default(nil)

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
            status: "absent",
            selected_candidate_id: nil,
            selected_candidate_event: nil,
            selected_candidate_checkpoint_kind: nil,
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
          when Events::AttemptAuthorizedV2
            rebuild(attempt_id: event.attempt_id, status: "authorized")
          when Events::AttemptAssignedToWorkItemV1
            rebuild(change_set_id: event.change_set_id, work_item_id: event.work_item_id)
          when Events::AttemptAssignedToAgentV1
            rebuild(agent_id: event.agent_id)
          when Events::AttemptBaseSnapshotRecordedV1
            snapshot = RepositorySnapshotV1.new(
              repository_id: event.repository_id,
              object_format: event.object_format,
              commit_oid: event.commit_oid
            )
            rebuild(base_snapshots: base_snapshots + [ snapshot ])
          when Events::AttemptStartedV2
            rebuild(status: "active")
          when Events::AttemptAbandonedV3
            rebuild(status: "abandoned")
          when Events::AttemptCompletedV2
            rebuild(status: "completed")
          when Events::WriteSetReservedV2
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
              status:,
              selected_candidate_id:,
              selected_candidate_event:,
              selected_candidate_checkpoint_kind:,
            )
          when Events::WriteSetExpandedV2
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              lease_repository_id: event.repository_id,
              lease_policy_version: event.policy_version,
              lease_resources: (lease_resources + event.added_resources).sort_by { _1.resource_id.b },
              lease_reserved_at:,
              lease_renewed_at:,
              lease_expires_at: event.expires_at,
              lease_released_at:,
              status:,
              selected_candidate_id:,
              selected_candidate_event:,
              selected_candidate_checkpoint_kind:,
            )
          when Events::WriteSetRenewedV2
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
              status:,
              selected_candidate_id:,
              selected_candidate_event:,
              selected_candidate_checkpoint_kind:,
            )
          when Events::WriteSetReleasedV2
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
              status:,
              selected_candidate_id:,
              selected_candidate_event:,
              selected_candidate_checkpoint_kind:,
            )
          when Events::CandidateAttachedToAttemptV1
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
              status:,
              selected_candidate_id: event.candidate_id,
              selected_candidate_event: event.candidate_event,
              selected_candidate_checkpoint_kind: event.checkpoint_kind,
            )
          else
            self
          end
        end

        private

        def rebuild(**changes)
          self.class.new(attributes.merge(changes))
        end
      end
    end
  end
end
