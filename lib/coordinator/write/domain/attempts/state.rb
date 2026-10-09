# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class State < Value
        Snapshot = Types.Instance(RepositorySnapshotV1)

        attribute :attempt_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 1)
        attribute :status, Types::String.enum("absent", "authorized", "active", "abandoned", "completed")

        def self.initial
          new(
            attempt_id: nil,
            change_set_id: nil,
            work_item_id: nil,
            agent_id: nil,
            base_snapshots: [],
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
